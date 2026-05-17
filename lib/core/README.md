# core/

Бутун ilova bo'ylab umumiy bo'lgan _texnik_ qatlam.

## Nimalar shu yerda:
- `theme/` — `AppTheme`, ranglar, typografiya
- `constants/` — global константалар (kanal nomlari, default qiymatlar)
- `errors/` — `AppException`, `Failure` turlari
- `extensions/` — `BuildContext`, `String` va boshqa extension'lar

## Qoidalar:
- `core/` faqat `utils/` va Flutter SDK ga bog'liq bo'lishi mumkin.
- Hech qachon `features/`, `repositories/`, `services/` ga bog'liq emas.
- Domain logikasi bu yerga tushmaydi.
