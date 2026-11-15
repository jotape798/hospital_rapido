"""Entrada do backend distribuível, sem dados ou credenciais embutidos."""

import os

import uvicorn


def main() -> int:
    host = os.getenv('UBS_BACKEND_HOST', '127.0.0.1')
    port = int(os.getenv('UBS_BACKEND_PORT', '8000'))
    uvicorn.run(
        'app.main:app',
        host=host,
        port=port,
        log_level=os.getenv('UBS_LOG_LEVEL', 'warning'),
        access_log=False,
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
