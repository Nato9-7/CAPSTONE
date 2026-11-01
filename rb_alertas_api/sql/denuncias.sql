-- Denuncias de reportes y comentarios hechas por los vecinos.
-- Cada fila apunta a un reporte O a un comentario (lo valida la API: MySQL no
-- permite CHECK sobre columnas con ON DELETE CASCADE). Si se borra lo
-- denunciado o la cuenta de quien denunció, la denuncia se borra con ellos.
CREATE TABLE IF NOT EXISTS denuncia (
    id_denuncia     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_usuario      BIGINT UNSIGNED NOT NULL,
    id_reporte      BIGINT UNSIGNED NULL,
    id_comentario   BIGINT UNSIGNED NULL,
    motivo          ENUM('FALSO', 'OFENSIVO', 'SPAM', 'DATOS_PERSONALES', 'OTRO') NOT NULL,
    detalle         VARCHAR(300) NULL,
    estado          ENUM('PENDIENTE', 'ATENDIDA', 'DESESTIMADA') NOT NULL DEFAULT 'PENDIENTE',
    fecha_creacion  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_revision  DATETIME NULL,
    id_admin        BIGINT UNSIGNED NULL,
    PRIMARY KEY (id_denuncia),
    -- Una denuncia por persona y por reporte o comentario.
    UNIQUE KEY uq_denuncia_reporte (id_usuario, id_reporte),
    UNIQUE KEY uq_denuncia_comentario (id_usuario, id_comentario),
    KEY ix_denuncia_estado (estado, fecha_creacion),
    CONSTRAINT fk_denuncia_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_denuncia_reporte FOREIGN KEY (id_reporte) REFERENCES reporte (id_reporte) ON DELETE CASCADE,
    CONSTRAINT fk_denuncia_comentario FOREIGN KEY (id_comentario) REFERENCES comentario (id_comentario) ON DELETE CASCADE,
    CONSTRAINT fk_denuncia_admin FOREIGN KEY (id_admin) REFERENCES usuario (id_usuario) ON DELETE SET NULL
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
