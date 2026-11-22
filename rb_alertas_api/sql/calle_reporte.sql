-- Calle normalizada de cada reporte, para el análisis por calle del panel.
-- La API la completa sola con geocodificación inversa (OpenStreetMap) al crear
-- el reporte; para los reportes anteriores: python -m scripts.completar_calles
ALTER TABLE reporte
    ADD COLUMN calle VARCHAR(150) NULL AFTER direccion_referencia,
    ADD INDEX idx_reporte_calle (calle);
