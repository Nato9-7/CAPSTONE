import mysql.connector.pooling as pooling

# Las rutas importan app.db, que abre MySQL al cargarse; en las pruebas no hace falta.
pooling.MySQLConnectionPool.__init__ = lambda self, **k: None

from app.rutas import admin  # noqa: E402


def preparar(tmp_path, monkeypatch):
    uploads = tmp_path / "uploads"
    (uploads / "reportes").mkdir(parents=True)
    monkeypatch.setattr(admin, "CARPETA_UPLOADS", uploads)
    return uploads


def test_borra_una_evidencia(tmp_path, monkeypatch):
    uploads = preparar(tmp_path, monkeypatch)
    foto = uploads / "reportes" / "foto.jpg"
    foto.write_bytes(b"x")
    assert admin._borrar_archivo("/uploads/reportes/foto.jpg") is True
    assert not foto.exists()


def test_no_sale_de_la_carpeta_de_uploads(tmp_path, monkeypatch):
    preparar(tmp_path, monkeypatch)
    secreto = tmp_path / "secreto.txt"
    secreto.write_text("no tocar")
    assert admin._borrar_archivo("/uploads/../secreto.txt") is False
    assert admin._borrar_archivo("/uploads/reportes/../../secreto.txt") is False
    assert secreto.exists()


def test_ignora_rutas_que_no_son_de_uploads(tmp_path, monkeypatch):
    preparar(tmp_path, monkeypatch)
    assert admin._borrar_archivo(None) is False
    assert admin._borrar_archivo("") is False
    assert admin._borrar_archivo("/etc/passwd") is False
    assert admin._borrar_archivo("https://otro.sitio/foto.jpg") is False
