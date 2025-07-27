# SyncRay

Una poderosa herramienta de sincronización de bases de datos basada en PowerShell que permite la migración de datos sin problemas entre bases de datos SQL Server con soporte completo para operaciones INSERT, UPDATE y DELETE.

![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-red)
![License](https://img.shields.io/badge/license-MIT-green)

## Características

- **Soporte CRUD completo**: Sincronizar tablas con operaciones INSERT, UPDATE y DELETE
- **Coincidencia inteligente**: Coincidencia de campos flexible más allá de las claves primarias
- **Modo Dry-Run**: Vista previa de cambios antes de la ejecución (comportamiento predeterminado)
- **Seguridad transaccional**: Todas las operaciones envueltas en transacciones con rollback automático
- **Validación integral**: Verificaciones previas para configuración, tablas y permisos
- **Filtrado de exportación**: Soporte de cláusula WHERE para exportación selectiva de datos
- **Manejo de identidad**: Soporte IDENTITY_INSERT configurable
- **Informes detallados**: Resúmenes de cambios formateados en tabla y estadísticas de ejecución

## Requisitos

- PowerShell 5.0 o superior
- SQL Server 2012 o superior
- Permisos de base de datos apropiados (SELECT, INSERT, UPDATE, DELETE)

## Inicio rápido

### Nuevo: Comando SyncRay central

La forma más fácil de usar SyncRay es a través del script central `syncray.ps1`:

```powershell
# Exportar desde producción
./src/syncray.ps1 -From production

# Importar a desarrollo (vista previa)
./src/syncray.ps1 -To development

# Sincronización directa de producción a desarrollo
./src/syncray.ps1 -From production -To development

# Analizar calidad de datos
./src/syncray.ps1 -From production -Analyze

# Obtener ayuda
./src/syncray.ps1 -Help
```

### Instrucciones de configuración

1. **Clonar el repositorio**
   ```bash
   git clone https://github.com/yourusername/SyncRay.git
   cd SyncRay
   ```

2. **Configurar sus bases de datos** en `src/sync-config.json`:
   ```json
   {
     "databases": {
       "prod": {
         "server": "PROD-SERVER",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "dev": {
         "server": "DEV-SERVER",
         "database": "DevelopmentDB",
         "auth": "sql",
         "user": "sa",
         "password": "password"
       }
     }
   }
   ```

3. **Usar SyncRay**:

   **Opción A: Usando el script central (recomendado)**
   ```powershell
   # Exportar datos
   ./src/syncray.ps1 -From prod
   
   # Importar datos (vista previa)
   ./src/syncray.ps1 -To dev
   
   # Sincronización directa
   ./src/syncray.ps1 -From prod -To dev -Execute
   ```

   **Opción B: Usando scripts individuales**
   ```powershell
   # Exportar
   ./src/sync-export.ps1 -From prod
   
   # Importar (vista previa)
   ./src/sync-import.ps1 -To dev
   
   # Importar (ejecutar)
   ./src/sync-import.ps1 -To dev -Execute
   ```

## Documentación

- [Guía de instalación](docs/installation.es.md)
- [Referencia de configuración](docs/configuration.es.md)
- [Ejemplos de uso](docs/examples.es.md)
- [Solución de problemas](docs/troubleshooting.es.md)

## Configuración

### Configuración de sincronización de tablas

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "targetTable": "Users_Archive",
    "matchOn": ["UserID"],
    "ignoreColumns": ["LastModified"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IsActive = 1"
  }]
}
```

### Parámetros clave

- **matchOn**: Campos para coincidencia de registros (detecta automáticamente la clave primaria si está vacío)
- **ignoreColumns**: Columnas a excluir de la comparación
- **allowInserts/Updates/Deletes**: Control de operaciones permitidas
- **exportWhere**: Filtrar datos de origen con cláusula SQL WHERE

## Referencia de comandos

### syncray.ps1 (Herramienta central)

El punto de entrada principal para todas las operaciones de SyncRay. Determina automáticamente la operación basándose en los parámetros.

**Parámetros:**
- `-From <string>`: Base de datos origen (activa el modo exportación)
- `-To <string>`: Base de datos destino (activa el modo importación)
- `-From <string> -To <string>`: Ambos (activa el modo sincronización)
- `-Analyze`: Analizar calidad de datos sin exportar
- `-Validate`: Validar configuración sin procesamiento
- `-Execute`: Aplicar cambios (para modos importación/sincronización)
- `-SkipOnDuplicates`: Omitir tablas con registros duplicados
- `-CreateReports`: Crear informes CSV para problemas
- `-ReportPath <string>`: Ruta personalizada para informes CSV
- `-CsvDelimiter <string>`: Delimitador CSV
- `-ShowSQL`: Mostrar declaraciones SQL para depuración
- `-Help`: Mostrar información de ayuda

**Ejemplos:**
```powershell
# Modo exportación
./src/syncray.ps1 -From production

# Modo importación (vista previa)
./src/syncray.ps1 -To development

# Modo sincronización (transferencia directa)
./src/syncray.ps1 -From production -To development -Execute

# Modo análisis
./src/syncray.ps1 -From production -Analyze
```

### sync-export.ps1

Exporta datos desde la base de datos origen a archivos JSON.

**Parámetros:**
- `-From <string>` (requerido): Clave de base de datos origen desde la configuración
- `-ConfigFile <string>`: Ruta al archivo de configuración (predeterminado: sync-config.json)
- `-Tables <string>`: Lista de tablas específicas separadas por comas para exportar
- `-Analyze`: Analizar calidad de datos y crear informes sin exportar
- `-Validate`: Validar configuración y datos sin exportar ni crear informes
- `-SkipOnDuplicates`: Omitir automáticamente tablas con registros duplicados
- `-CreateReports`: Crear informes CSV para problemas de calidad de datos
- `-ReportPath <string>`: Ruta personalizada para informes CSV
- `-CsvDelimiter <string>`: Delimitador CSV (predeterminado: específico de la cultura)
- `-ShowSQL`: Mostrar declaraciones SQL e información de depuración detallada

**Ejemplos de uso:**
```powershell
# Exportación estándar
./src/sync-export.ps1 -From prod

# Exportar con informes de problemas
./src/sync-export.ps1 -From prod -CreateReports

# Solo analizar calidad de datos
./src/sync-export.ps1 -From prod -Analyze

# Exportar tablas específicas con salida SQL de depuración
./src/sync-export.ps1 -From prod -Tables "Users,Orders" -ShowSQL
```

### sync-import.ps1

Importa datos desde archivos JSON a la base de datos destino.

**Parámetros:**
- `-To <string>` (requerido): Clave de base de datos destino desde la configuración
- `-ConfigFile <string>`: Ruta al archivo de configuración (predeterminado: sync-config.json)
- `-Tables <string>`: Lista de tablas específicas separadas por comas para importar
- `-Execute`: Aplicar cambios (predeterminado es dry-run)
- `-ShowSQL`: Mostrar declaraciones SQL para depuración

## Características de seguridad

- **Validación primero**: Verificaciones previas integrales antes de cualquier operación
- **Dry-Run predeterminado**: Siempre vista previa de cambios antes de la ejecución
- **Confirmación de seguridad**: Se requiere confirmación explícita para la ejecución
- **Rollback de transacción**: Rollback automático en caso de error
- **Detección de duplicados**: Asegura que los campos matchOn identifiquen registros únicos

## Salida de ejemplo

```
=== CAMBIOS DETECTADOS ===

Tabla                    | Insertar | Actualizar | Eliminar
-----------------------------------------------------------
Users                    |      125 |         37 |        5
Orders                   |      450 |          0 |        0
Products                 |        0 |         15 |        2
-----------------------------------------------------------
TOTAL                    |      575 |         52 |        7

ADVERTENCIA: ¡Está a punto de modificar la base de datos!

¿Desea ejecutar estos cambios? (sí/no):
```

## Contribuir

¡Las contribuciones son bienvenidas! No dude en enviar una solicitud de extracción (Pull Request).

## Licencia

Este proyecto está licenciado bajo la Licencia MIT - vea el archivo [LICENSE](LICENSE) para más detalles.

## Agradecimientos

- Construido con PowerShell y SQL Server
- Inspirado por la necesidad de sincronización confiable de bases de datos

---

Desarrollado por el equipo Raycoon