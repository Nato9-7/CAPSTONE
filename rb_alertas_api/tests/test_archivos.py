from app.comun import archivos


def preparar(tmp_path, monkeypatch):
    uploads = tmp_path / "uploads"
    (uploads / "reportes").mkdir(parents=True)
    monkeypatch.setattr(archivos, "CARPETA_UPLOADS", uploads)
    return uploads


def test_borra_una_evidencia(tmp_path, monkeypatch):
    uploads = preparar(tmp_path, monkeypatch)
    foto = uploads / "reportes" / "foto.jpg"
    foto.write_bytes(b"x")
    assert archivos.borrar_archivo("/uploads/reportes/foto.jpg") is True
    assert not foto.exists()


def test_no_sale_de_la_carpeta_de_uploads(tmp_path, monkeypatch):
    preparar(tmp_path, monkeypatch)
    secreto = tmp_path / "secreto.txt"
    secreto.write_text("no tocar")
    assert archivos.borrar_archivo("/uploads/../secreto.txt") is False
    assert archivos.borrar_archivo("/uploads/reportes/../../secreto.txt") is False
    assert secreto.exists()


def test_ignora_rutas_que_no_son_de_uploads(tmp_path, monkeypatch):
    preparar(tmp_path, monkeypatch)
    assert archivos.borrar_archivo(None) is False
    assert archivos.borrar_archivo("") is False
    assert archivos.borrar_archivo("/etc/passwd") is False
    assert archivos.borrar_archivo("https://otro.sitio/foto.jpg") is False


def test_borrar_varios_cuenta_los_borrados(tmp_path, monkeypatch):
    uploads = preparar(tmp_path, monkeypatch)
    (uploads / "reportes" / "a.jpg").write_bytes(b"x")
    assert archivos.borrar_archivos(["/uploads/reportes/a.jpg", "/etc/passwd"]) == 1


def test_detecta_formato_por_contenido_y_no_por_nombre():
    assert archivos.detectar_formato(b"\xff\xd8\xff\xe0resto") == ".jpg"
    assert archivos.detectar_formato(b"\x89PNG\r\n\x1a\nresto") == ".png"
    assert archivos.detectar_formato(b"RIFF\x00\x00\x00\x00WEBPVP8 ") == ".webp"
    assert archivos.detectar_formato(b"\x00\x00\x00\x18ftypheic") == ".heic"
    assert archivos.detectar_formato(b"\x00\x00\x00\x14ftypqt  ") == ".mov"
    assert archivos.detectar_formato(b"\x00\x00\x00\x18ftypisom") == ".mp4"
    assert archivos.detectar_formato(b"%PDF-1.7") is None
