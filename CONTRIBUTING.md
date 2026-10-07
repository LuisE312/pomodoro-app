# Cómo contribuir

¡Gracias por querer mejorar Pomodoro App! Toda ayuda es bienvenida:
código, ideas, traducciones, reportes de errores y documentación.

## Reportar un error o proponer una idea
Abre un [issue](../../issues) y cuéntanos:
- Qué esperabas que pasara y qué pasó.
- Modelo de teléfono y versión de Android.
- Pasos para reproducirlo, si es un error.

## Enviar código
1. Haz un *fork* del repositorio y clónalo.
2. Crea una rama: `git checkout -b feat/mi-mejora`
3. Instala dependencias: `flutter pub get`
4. Haz tus cambios y verifica que todo pase:
       flutter analyze
       flutter test
5. Haz commit con un mensaje claro (por ejemplo `feat: añade tema manual`).
6. Sube tu rama y abre un *pull request* explicando qué cambia y por qué.

## Estilo
- Formatea el código con `dart format .` antes de enviarlo.
- Mantén los cambios pequeños y enfocados: un PR, una idea.
- Si añades lógica nueva, añade también una prueba.

## Ideas para empezar
- Interruptor manual de tema claro/oscuro.
- Traducción a otros idiomas.
- Funcionamiento con la pantalla bloqueada.
- Elegir distintos sonidos de aviso.