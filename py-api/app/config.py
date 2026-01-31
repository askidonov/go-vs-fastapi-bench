import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "benchdb"
    db_user: str = "benchuser"
    db_password: str = "benchpass"
    db_pool_min_size: int = 10
    db_pool_max_size: int = 100
    server_port: int = 8081

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
