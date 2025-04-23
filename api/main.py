# Plik: main.py
import os
import datetime
from typing import List, Optional, Annotated
from fastapi.middleware.cors import CORSMiddleware
from datetime import timedelta

# --- Zależności ---
# Zainstaluj w venv: pip install "fastapi[all]" motor beanie pydantic-settings passlib[bcrypt] python-dotenv
from fastapi import FastAPI, HTTPException, status, Body, Depends, Query
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, Field, EmailStr, model_validator
from pydantic_settings import BaseSettings
from jose import JWTError, jwt
from beanie import Document, Link, init_beanie, PydanticObjectId
import motor.motor_asyncio
from passlib.context import CryptContext
from contextlib import asynccontextmanager

# --- Konfiguracja (użyjemy .env) ---
class Settings(BaseSettings):
    mongo_uri: str = "mongodb://localhost:27017"
    database_name: str = "calorie_tracker_db_fastapi"
    jwt_secret_key: str = "da401869d8e6e69d5df3693505014b302c5d43658f12e28b6f38fec27fb03cbe"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30  # Dodaj nową zmienną

    class Config:
        env_file = '.env' # Wczyta zmienne z pliku .env
        env_file_encoding = 'utf-8' # Dodaj kodowanie dla pewności

settings = Settings()

# Inicjalizacja OAuth2
# tokenUrl="/token" wskazuje, gdzie klient powinien wysłać żądanie tokena
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Dodaj nowe modele Tokenów
class Token(BaseModel):
    access_token: str
    token_type: str
    # Opcjonalnie możesz dodać informacje o użytkowniku do tokena, np.:
    # user_info: UserPublic # Wymagałoby to zaktualizowania endpointu /token

class TokenData(BaseModel):
    username: Optional[str] = None

# --- Kontekst hashowania haseł ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- Modele danych (Pydantic i Beanie) ---

# Model Użytkownika (Beanie Document - zapis w DB)
class User(Document):
    username: str = Field(..., index=True, unique=True)
    email: Optional[EmailStr] = Field(default=None, index=True, unique=True, validate_default=False) # Poprawka dla None
    hashed_password: str
    daily_calorie_goal: Optional[int] = Field(default=2000, gt=0)
    is_active: bool = Field(default=True)

    class Settings:
        name = "users"

# Model do tworzenia użytkownika (Pydantic BaseModel - dane wejściowe)
class UserCreate(BaseModel):
    username: str
    email: Optional[EmailStr] = None
    password: str = Field(..., min_length=6)
    daily_calorie_goal: Optional[int] = 2000

# Model do wyświetlania użytkownika (bez hasła)
class UserPublic(BaseModel):
    # Beanie/Pydantic mapuje _id z Mongo na pole 'id' typu PydanticObjectId
    # które Flutter odczyta jako string. Alias zapewnia kompatybilność.
    id: PydanticObjectId = Field(..., alias="_id")
    username: str
    email: Optional[EmailStr] = None
    daily_calorie_goal: Optional[int]
    is_active: bool

    class Config:
        populate_by_name = True # Umożliwia aliasowanie _id na id
        from_attributes = True  # Pozwala na tworzenie z obiektu User (ORM mode)
        json_encoders = { PydanticObjectId: str } # Upewnia się, że ID jest stringiem w JSON

# Model Produktu Spożywczego (Beanie Document)
class FoodItem(Document):
    name: str = Field(..., index=True)
    calories_per_100g: float = Field(..., gt=0)
    protein_per_100g: Optional[float] = Field(default=None, ge=0)
    carbs_per_100g: Optional[float] = Field(default=None, ge=0)
    fat_per_100g: Optional[float] = Field(default=None, ge=0)

    class Settings:
        name = "food_items"
        # Beanie automatycznie doda pole `id: PydanticObjectId` mapowane na `_id`

# Model do tworzenia produktu (Pydantic BaseModel)
class FoodItemCreate(BaseModel):
    name: str
    calories_per_100g: float
    protein_per_100g: Optional[float] = None
    carbs_per_100g: Optional[float] = None
    fat_per_100g: Optional[float] = None

# Model Wpisu w Dzienniku (Beanie Document)
class LogEntry(Document):
    user: Link[User]
    food_item: Optional[Link[FoodItem]] = None
    custom_food_name: Optional[str] = None
    custom_calories_per_100g: Optional[float] = None
    grams: float = Field(..., gt=0)
    total_calories: float = Field(..., ge=0)
    # Pydantic domyślnie serializuje datetime do ISO 8601, co odczytuje Dart `DateTime.parse`
    timestamp: datetime.datetime = Field(default_factory=datetime.datetime.now)

    class Settings:
        name = "log_entries"
        # Beanie automatycznie doda pole `id: PydanticObjectId`

# Model do tworzenia wpisu (Pydantic BaseModel)
class LogEntryCreate(BaseModel):
    # Nie potrzebujemy już user_id bezpośrednio w tym modelu,
    # ID użytkownika będzie pochodzić z tokena
    food_item_id: Optional[PydanticObjectId] = None
    custom_food_name: Optional[str] = None
    custom_calories_per_100g: Optional[float] = None
    grams: float

    @model_validator(mode='before')
    @classmethod
    def check_food_source(cls, values):
        food_id = values.get('food_item_id')
        custom_name = values.get('custom_food_name')
        custom_cals = values.get('custom_calories_per_100g')

        # Sprawdzenie istnienia kluczy i wartości None
        has_food_id = food_id is not None
        has_custom_name = custom_name is not None and custom_name != ""
        has_custom_cals = custom_cals is not None

        if has_food_id and (has_custom_name or has_custom_cals):
            raise ValueError("Nie można podać jednocześnie 'food_item_id' oraz danych przekąski ('custom_food_name', 'custom_calories_per_100g')")
        if not has_food_id and not (has_custom_name and has_custom_cals):
            raise ValueError("Należy podać 'food_item_id' lub parę 'custom_food_name' i 'custom_calories_per_100g'")
        if has_custom_cals is not None and custom_cals <= 0: # Poprawione sprawdzenie na None
             raise ValueError("'custom_calories_per_100g' musi być wartością dodatnią")
        if has_custom_name and not has_custom_cals:
             raise ValueError("Jeśli podajesz 'custom_food_name', musisz też podać 'custom_calories_per_100g'")
        if not has_custom_name and has_custom_cals:
            raise ValueError("Jeśli podajesz 'custom_calories_per_100g', musisz też podać 'custom_food_name'")

        return values

# Model podsumowania dziennego
class DailySummary(BaseModel):
    # Pydantic domyślnie serializuje date do "YYYY-MM-DD", co odczytuje Dart (z małą adaptacją)
    date: datetime.date
    # Nie potrzebujemy już user_id w DailySummary dla response_model
    # ale możemy go zachować dla przejrzystości
    user_id: PydanticObjectId = Field(..., alias="_id") # Dodane aliasowanie dla spójności
    username: str
    daily_calorie_goal: Optional[int]
    total_calories_consumed: float
    calories_remaining: Optional[float]
    logged_entries: List[LogEntry]

    class Config:
         populate_by_name = True # Umożliwia aliasowanie _id na id
         from_attributes = True  # Pozwala na tworzenie z obiektu User (ORM mode)
         json_encoders = { PydanticObjectId: str } # Upewnia się, że ID jest stringiem w JSON

# --- Inicjalizacja Bazy Danych i FastAPI ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"Connecting to MongoDB at: {settings.mongo_uri} / DB: {settings.database_name}")
    client = motor.motor_asyncio.AsyncIOMotorClient(settings.mongo_uri)
    try:
        # Sprawdź połączenie przed inicjalizacją Beanie
        await client.admin.command('ping')
        print("MongoDB connection successful (ping).")
    except Exception as e:
        print(f"FATAL: Could not connect to MongoDB: {e}")
        # Można tu rzucić wyjątek, aby zatrzymać start aplikacji, jeśli baza jest krytyczna
        # raise RuntimeError(f"Could not connect to MongoDB: {e}") from e
        # Lub pozwolić na start, ale API będzie zwracać błędy
    db = client[settings.database_name]
    await init_beanie(
        database=db,
        document_models=[
            User,
            FoodItem,
            LogEntry,
        ]
    )
    print(f"Beanie initialized with DB: {settings.database_name}")
    yield
    print("Closing MongoDB connection...")
    client.close()
    print("Connection closed.")

app = FastAPI(
    title="Calorie Tracker API",
    description="API do śledzenia kalorii spożywanych posiłków.",
    version="0.1.0",
    lifespan=lifespan
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins (for development only)
    allow_credentials=True,
    allow_methods=["*"],  # Allows all HTTP methods (GET, POST, OPTIONS, etc.)
    allow_headers=["*"],  # Allows all headers
)

# --- Funkcje pomocnicze ---
def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

# Ta funkcja nie jest używana jako FastAPI Dependency, ale jest potrzebna dla skryptu create_user
async def get_user_by_username(username: str) -> Optional[User]:
     return await User.find_one(User.username == username)

async def get_user_by_email(email: EmailStr) -> Optional[User]:
     return await User.find_one(User.email == email)

# Zmodyfikuj funkcję authenticate_user
async def authenticate_user(username: str, password: str) -> Optional[User]:
    user = await User.find_one(User.username == username)
    if not user or not verify_password(password, user.hashed_password):
        return None
    # Dodaj sprawdzenie czy użytkownik jest aktywny
    if not user.is_active:
        return None # Nie autentykuj nieaktywnych użytkowników
    return user

# Dodaj funkcje do pracy z JWT
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.datetime.now(datetime.timezone.utc) + expires_delta
    else:
        # Domyślnie 15 minut, jeśli nie podano expires_delta
        expire = datetime.datetime.now(datetime.timezone.utc) + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)

# Dependency do pobierania aktualnego użytkownika z tokena
async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        username: str = payload.get("sub") # 'sub' to standardowe pole JWT dla "subject"
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError:
        raise credentials_exception

    # Pobierz użytkownika z bazy danych na podstawie nazwy użytkownika z tokena
    user = await User.find_one(User.username == token_data.username)
    if user is None:
        raise credentials_exception
    # Opcjonalnie sprawdź, czy użytkownik nadal jest aktywny
    if not user.is_active:
         raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, # Lub 401/403
            detail="Użytkownik jest nieaktywny",
        )
    return user

# Dependency do pobierania aktualnego aktywnego użytkownika
async def get_current_active_user(current_user: Annotated[User, Depends(get_current_user)]) -> User:
    # get_current_user już sprawdza aktywność, więc można użyć bezpośrednio
    return current_user


# --- Endpointy API ---

# === Autentykacja i Użytkownicy ===

@app.post(
    "/register",
    response_model=UserPublic,
    status_code=status.HTTP_201_CREATED,
    tags=["Auth"],
    summary="Zarejestruj nowego użytkownika"
)
async def register_user(user_data: UserCreate):
    existing_user = await get_user_by_username(user_data.username)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Nazwa użytkownika '{user_data.username}' jest już zajęta."
        )
    if user_data.email:
        existing_email = await get_user_by_email(user_data.email)
        if existing_email:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Adres email '{user_data.email}' jest już używany."
            )

    hashed_password = get_password_hash(user_data.password)
    user = User(
        username=user_data.username,
        email=user_data.email,
        hashed_password=hashed_password,
        daily_calorie_goal=user_data.daily_calorie_goal,
        is_active=True # Domyślnie nowy użytkownik jest aktywny
    )
    await user.insert()
    return user

# Zmień endpoint /login na OAuth2 zgodny (/token)
@app.post(
    "/token",
    response_model=Token,
    tags=["Auth"],
    summary="Pobierz token JWT dla zalogowanego użytkownika"
)
async def login_for_access_token(
    # Użyj Depends(OAuth2PasswordRequestForm) do pobrania danych (username i password)
    # z żądania application/x-www-form-urlencoded, co jest standardem OAuth2
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()]
):
    # Użyj zmodyfikowanej funkcji authenticate_user, która sprawdzi też aktywność
    user = await authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password or user inactive",
            headers={"WWW-Authenticate": "Bearer"}, # Ważne dla standardu OAuth2
        )
    access_token_expires = timedelta(minutes=settings.jwt_access_token_expire_minutes)
    access_token = create_access_token(
        # W tokenie umieszczamy username ('sub') jako identyfikator użytkownika
        data={"sub": user.username},
        expires_delta=access_token_expires
    )
    # Zwracamy obiekt Token z access_token i token_type
    return {"access_token": access_token, "token_type": "bearer"}


# Dodaj endpoint do pobierania danych zalogowanego użytkownika
@app.get("/users/me/", response_model=UserPublic, tags=["Users"], summary="Pobierz dane zalogowanego użytkownika")
async def read_users_me(
    current_user: Annotated[User, Depends(get_current_active_user)] # Używamy Dependency
):
    # Dependency get_current_active_user już zwróciła obiekt User, więc po prostu go zwracamy
    return current_user

# Dodaj endpoint do pobierania danych użytkownika po ID (wymaga autoryzacji)
@app.get("/users/{user_id}", response_model=UserPublic, tags=["Users"], summary="Pobierz dane użytkownika po ID")
async def read_user(
    user_id: PydanticObjectId,
    current_user: Annotated[User, Depends(get_current_active_user)] # Używamy Dependency
):
    # Opcjonalnie możesz sprawdzić, czy zalogowany użytkownik ma prawo zobaczyć dane tego konkretnego użytkownika
    # W tym przypadku pozwolimy każdemu zalogowanemu użytkownikowi zobaczyć dane każdego innego użytkownika
    # Jeśli chcesz ograniczyć dostęp np. tylko do własnych danych, dodaj logikę:
    # if current_user.id != user_id:
    #     raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this user's data")

    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user

# === Produkty Spożywcze ===
# Zmodyfikuj istniejące endpointy aby wymagały autentykacji
@app.post(
    "/foods",
    response_model=FoodItem,
    status_code=status.HTTP_201_CREATED,
    tags=["Foods"],
    summary="Dodaj nowy produkt spożywczy do globalnej bazy",
    dependencies=[Depends(get_current_active_user)] # Dodaj dependency do autentykacji
)
async def add_food_item(food: FoodItemCreate):
    existing_food = await FoodItem.find_one(FoodItem.name == food.name)
    if existing_food:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Produkt o nazwie '{food.name}' już istnieje."
        )
    new_food = FoodItem(**food.model_dump())
    await new_food.insert()
    return new_food

@app.get(
    "/foods",
    response_model=List[FoodItem],
    tags=["Foods"],
    summary="Pobierz listę produktów spożywczych (z opcją wyszukiwania)",
    dependencies=[Depends(get_current_active_user)] # Dodaj dependency do autentykacji
)
async def search_food_items(search: Optional[str] = Query(None, min_length=1, description="Tekst do wyszukania w nazwie produktu")):
    query = {}
    if search:
        query = {"name": {"$regex": search, "$options": "i"}}
    food_items = await FoodItem.find(query).to_list()
    return food_items


# === Logowanie Posiłków ===
# Zmodyfikuj endpoint /log
@app.post(
    "/log",
    response_model=LogEntry,
    status_code=status.HTTP_201_CREATED,
    tags=["Logging"],
    summary="Zaloguj spożyty posiłek lub przekąskę"
)
async def log_meal_or_snack(
    log_data: LogEntryCreate,
    current_user: Annotated[User, Depends(get_current_user)]  # Pobierz użytkownika z tokena
):
    total_calories: float = 0.0
    food_item_link: Optional[Link[FoodItem]] = None
    final_custom_name: Optional[str] = None
    final_custom_cals_100g: Optional[float] = None

    if log_data.food_item_id:
        food_item = await FoodItem.get(log_data.food_item_id)
        if not food_item:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"FoodItem with id '{log_data.food_item_id}' not found")
        total_calories = (food_item.calories_per_100g / 100.0) * log_data.grams
        food_item_link = food_item  # Beanie automatycznie konwertuje do Link
    elif log_data.custom_food_name and log_data.custom_calories_per_100g is not None:
        total_calories = (log_data.custom_calories_per_100g / 100.0) * log_data.grams
        final_custom_name = log_data.custom_food_name
        final_custom_cals_100g = log_data.custom_calories_per_100g

    log_entry = LogEntry(
        user=current_user,  # Beanie automatycznie konwertuje do Link
        food_item=food_item_link,
        custom_food_name=final_custom_name,
        custom_calories_per_100g=final_custom_cals_100g,
        grams=log_data.grams,
        total_calories=round(total_calories, 2),
    )
    await log_entry.insert()
    return log_entry

# Zmodyfikuj endpoint /log/summary/today
@app.get(
    "/log/summary/today",
    response_model=DailySummary,
    tags=["Logging"],
    summary="Pobierz podsumowanie kalorii i wpisów z dzisiejszego dnia dla zalogowanego użytkownika"
)
async def get_daily_summary(
    current_user: Annotated[User, Depends(get_current_active_user)] # Zależność dostarcza zalogowanego użytkownika
):
    # Użyj current_user.id zamiast parametru user_id
    user_id = current_user.id
    user = current_user # Używamy obiektu użytkownika dostarczonego przez Depends

    today = datetime.date.today()
    start_of_day = datetime.datetime.combine(today, datetime.time.min).replace(tzinfo=datetime.timezone.utc)
    end_of_day = datetime.datetime.combine(today, datetime.time.max).replace(tzinfo=datetime.timezone.utc)
    # Można też użyć tzlocal jeśli timestampy zapisywane są w lokalnej strefie czasowej

    entries_today = await LogEntry.find(
        LogEntry.user.id == user.id, # Porównanie po ID wewnątrz Linku
        LogEntry.timestamp >= start_of_day,
        LogEntry.timestamp <= end_of_day,
        fetch_links=True # <-- Kluczowe dla Fluttera, aby dostał pełne dane FoodItem
    ).sort("+timestamp").to_list()

    total_calories_consumed = sum(entry.total_calories for entry in entries_today)

    calories_remaining = None
    if user.daily_calorie_goal is not None:
        calories_remaining = max(0.0, float(user.daily_calorie_goal) - total_calories_consumed)

    # Tworzymy DailySummary z danych użytkownika i obliczeń
    summary = DailySummary(
        date=today, # Zwracamy samą datę
        _id=user.id, # Używamy aliasu '_id' do przekazania ID użytkownika
        username=user.username,
        daily_calorie_goal=user.daily_calorie_goal,
        total_calories_consumed=round(total_calories_consumed, 2),
        calories_remaining=round(calories_remaining, 2) if calories_remaining is not None else None,
        logged_entries=entries_today # Lista obiektów LogEntry (z zagnieżdżonymi FoodItem)
    )
    return summary


# --- Uruchomienie serwera (dla celów deweloperskich) ---
if __name__ == "__main__":
    import uvicorn
    print("Starting Uvicorn server...")
    # Uruchom na wszystkich interfejsach (0.0.0.0), port 8000, z auto-reload
    # Zmień port jeśli 8000 jest zajęty.
    # Użyj --host 0.0.0.0 aby API było dostępne w sieci lokalnej (dla testów z Flutterem)
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
