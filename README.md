# GrindNimals

Proyecto Roblox multi-Place administrado con Rojo.

## Places

- **BlockFarm** — lobby / mundo principal.
- **CasaJugadores** — exterior de las casas de jugadores.
- **AdentroCasaJugadores** — interiores de las casas.
- **Jardín** — se mantiene como zona vinculada al interior/exterior; no se trata como un Place independiente por ahora.

Cada Place tiene su propio archivo `.project.json` y su propia carpeta dentro de `src/`.

## Archivos de proyecto

- `BlockFarm.project.json`
- `CasaJugadores.project.json`
- `AdentroCasaJugadores.project.json`

## Seguridad al conectar Studio

Los proyectos usan `$ignoreUnknownInstances: true` en los servicios administrados para evitar que una primera conexión de Rojo elimine objetos existentes que todavía no hayan sido llevados al repositorio.

## Próximo paso

1. Clonar este repositorio en la PC.
2. Guardar/exportar una copia local de cada Place de Roblox Studio.
3. Ejecutar `rojo syncback` por separado para cada Place usando su archivo de proyecto correspondiente.
4. Revisar los cambios antes de usar `rojo serve` sobre la versión principal del juego.
