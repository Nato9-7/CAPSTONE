"""Fotos y videos que adjuntan los vecinos, guardados en la carpeta de uploads."""

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException, UploadFile

log = logging.getLogger("rb_alertas.archivos")

# En Docker esta carpeta debe montarse como volumen; si no, las evidencias
# se pierden al recrear el contenedor. El volumen debe pertenecer al usuario
# con que corre la API (en la imagen, appuser).
CARPETA_UPLOADS = Path(os.getenv("CARPETA_UPLOADS", Path(__file__).resolve().parents[2] / "uploads"))
PREFIJO_URL = "/uploads/"

FORMATOS_FOTO = (".jpg", ".png", ".webp", ".heic")
FORMATOS_VIDEO = (".mp4", ".mov", ".webm")


def detectar_formato(contenido: bytes) -> str | None:
    """Extensión según la firma real del archivo; None si no es una foto o video aceptado.

    Se mira el contenido y no el Content-Type ni el nombre, que los controla el cliente.
    """
    if contenido.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if contenido.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if contenido[:4] == b"RIFF" and contenido[8:12] == b"WEBP":
        return ".webp"
    if contenido.startswith(b"\x1a\x45\xdf\xa3"):
        return ".webm"
    if contenido[4:8] == b"ftyp":
        marca = contenido[8:12]
        if marca in (b"heic", b"heix", b"mif1", b"msf1", b"hevc"):
            return ".heic"
        if marca == b"qt  ":
            return ".mov"
        return ".mp4"
    return None


def _preparar_carpeta(carpeta: Path) -> bool:
    """Crea la carpeta y dice si se puede escribir en ella.

    Si no se puede, la API arranca igual y solo rechaza los adjuntos: sin esto,
    un problema de permisos tumba toda la API.
    """
    try:
        carpeta.mkdir(parents=True, exist_ok=True)
        disponible = os.access(carpeta, os.W_OK)
    except OSError:
        disponible = False
    if not disponible:
        log.error("No se puede escribir en %s: se aceptan los datos, pero sin adjuntos", carpeta)
    return disponible


@dataclass
class CarpetaAdjuntos:
    """Subcarpeta de uploads con sus reglas de tamaño, formato y mensajes de error."""

    subcarpeta: str
    tamano_maximo: int
    formatos: tuple[str, ...]
    mensaje_no_disponible: str
    mensaje_tamano: str
    mensaje_formato: str
    ruta: Path = field(init=False)
    disponible: bool = field(init=False)

    def __post_init__(self) -> None:
        self.ruta = CARPETA_UPLOADS / self.subcarpeta
        self.disponible = _preparar_carpeta(self.ruta)

    def guardar(self, archivo: UploadFile) -> tuple[Path, str]:
        """Valida y guarda el archivo. Devuelve (ruta en disco, url pública)."""
        if not self.disponible:
            raise HTTPException(status_code=503, detail=self.mensaje_no_disponible)
        contenido = archivo.file.read(self.tamano_maximo + 1)
        if len(contenido) > self.tamano_maximo:
            raise HTTPException(status_code=413, detail=self.mensaje_tamano)
        extension = detectar_formato(contenido)
        if extension not in self.formatos:
            raise HTTPException(status_code=415, detail=self.mensaje_formato)
        nombre_archivo = f"{uuid4().hex}{extension}"
        ruta = self.ruta / nombre_archivo
        ruta.write_bytes(contenido)
        return ruta, f"{PREFIJO_URL}{self.subcarpeta}/{nombre_archivo}"


def hay_archivo(archivo: UploadFile | None) -> bool:
    return archivo is not None and bool(archivo.filename)


def borrar_archivo(url: str | None) -> bool:
    """Borra del disco un adjunto ("/uploads/...") sin salir de la carpeta de uploads."""
    if not url or not url.startswith(PREFIJO_URL):
        return False
    base = Path(CARPETA_UPLOADS).resolve()
    ruta = (base / url.removeprefix(PREFIJO_URL)).resolve()
    if base not in ruta.parents:
        return False
    try:
        ruta.unlink(missing_ok=True)
        return True
    except OSError as error:
        log.warning("No se pudo borrar %s: %s", ruta, error)
        return False


def borrar_archivos(urls: list[str]) -> int:
    """Borra varios adjuntos y devuelve cuántos se borraron."""
    return sum(borrar_archivo(url) for url in urls)
