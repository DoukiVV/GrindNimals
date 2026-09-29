# GrindNimals

Proyecto Roblox multi-Place administrado con Rojo.

## Places reales de la experiencia

- **GrindNimals** — mundo principal / lobby.
- **CasaJugadores** — exterior de las casas de jugadores.
- **AdentroCasaJugadores** — interiores de las casas.
- **Reserva natural** — mundo de reserva natural.
- **Pruebas** — excluido del repositorio principal por ahora.

Cada Place tiene su propio archivo `.project.json` y su propia carpeta dentro de `src/`.

## Archivos de proyecto

- `GrindNimals.project.json`
- `CasaJugadores.project.json`
- `AdentroCasaJugadores.project.json`
- `ReservaNatural.project.json`

> Nota: el archivo y la carpeta usan `ReservaNatural` sin espacio para facilitar comandos y rutas, pero corresponde al Place visible como **Reserva natural** en Roblox Studio.

## Seguridad al conectar Studio

Los proyectos usan `$ignoreUnknownInstances: true` en los servicios administrados para evitar que una primera conexión de Rojo elimine objetos existentes que todavía no hayan sido llevados al repositorio.

## Flujo recomendado

1. Clonar este repositorio en la PC.
2. Guardar/exportar una copia local de cada Place de Roblox Studio.
3. Ejecutar `rojo syncback` por separado para cada Place usando su archivo de proyecto correspondiente.
4. Revisar los cambios antes de usar `rojo serve` sobre la versión principal del juego.
