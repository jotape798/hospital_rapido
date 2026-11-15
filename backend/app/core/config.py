"""Configuração exclusiva do servidor; nenhum segredo tem valor padrão."""
import os
from pathlib import Path
from urllib.parse import urlsplit
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / '.env')
SECRET = os.getenv('JWT_SECRET_KEY', '')
ALGORITHM = 'HS256'
ORIGINS = [x.strip() for x in os.getenv('ALLOWED_ORIGINS', 'http://localhost:8080,http://127.0.0.1:8080').split(',') if x.strip()]

def check_config():
    if len(SECRET) < 32 or SECRET.startswith('troque'):
        raise RuntimeError('Configure JWT_SECRET_KEY com uma chave aleatória de pelo menos 32 caracteres no backend/.env.')
    environment = os.getenv('APP_ENV', 'development').strip().lower()
    if not ORIGINS:
        raise RuntimeError('Configure ao menos uma origem em ALLOWED_ORIGINS.')
    for origin in ORIGINS:
        parsed = urlsplit(origin)
        if parsed.scheme not in {'http', 'https'} or not parsed.netloc or parsed.path not in {'', '/'} or parsed.query or parsed.fragment:
            raise RuntimeError(f'Origem CORS inválida: {origin}')
        if environment == 'production' and parsed.scheme != 'https':
            raise RuntimeError('Todas as origens CORS devem usar HTTPS em produção.')
