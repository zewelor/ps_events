# Odpowiedzi API `POST /events_ocr`

Endpoint wykonuje jedną próbę OCR przesłanego obrazu z opcjonalnym tekstem.
Dla uwierzytelniania Bearer limit czasu żądania do modelu wynosi 300 sekund.
PDF-y obsługują narzędzia CLI i benchmark, a endpoint przyjmuje obrazy.

## Kody i komunikaty

| HTTP | Pole rozpoznawcze | `message` | Działanie klienta |
| --- | --- | --- | --- |
| 401 | `status: "error"` | `Authentication required` lub `Google authentication failed: …` | Poproś o poprawne uwierzytelnienie. |
| 403 | `status: "error"` | `Email not authorized` lub `Forbidden origin` | Sprawdź uprawnienia konta lub nagłówek `Origin`. |
| 422 | `status: "error"`, bez `error_code` | `Selecione uma imagem.`, `As informações adicionais não podem exceder 5000 caracteres`, komunikat przetwarzania obrazu lub `Erro ao analisar imagem: …`. Ogólny wyjątek zwraca swoją treść. | Pokaż komunikat. Przy błędzie wejścia popraw dane i wyślij ponownie. |
| 422 | `error_code: "ocr_review_required"` | `A análise contém informações que precisam de revisão. Nenhum evento foi submetido.` | Pokaż `review_items` do ręcznej korekty. `events` jest puste. Arkusz i publikacja obrazu nie zostały zmienione. |
| 429 | `error_code: "rate_limit_exceeded"` | `Limite de pedidos/quota do modelo LLM excedido: …` | Ponawiaj z rosnącym odstępem i ograniczoną liczbą prób tylko przy `retry_safe: true`. Flaga oznacza, że błąd wystąpił w analizie, przed zapisem. Ten sam kod obejmuje zarówno chwilowy limit, jak i wyczerpanie limitu użycia. |
| 503 | `error_code: "ocr_temporarily_unavailable"` | `O serviço de análise está temporariamente indisponível. Tente novamente mais tarde.` | Ponawiaj z rosnącym odstępem i ograniczoną liczbą prób. Błąd wystąpił podczas analizy, przed zapisem. |
| 503 | `error_code: "ingestion_failed"` | `Não foi possível concluir a submissão. Adicionados: {added}. Já existentes: {skipped}. A aguardar revisão: {conflicted}. Os dados foram mantidos. Verifique os eventos antes de tentar novamente.` | Pokaż dotychczasowe wyniki. Przed ponowieniem sprawdź arkusz, ponieważ część operacji mogła się udać. |
| 409 | `status: "needs_review"`, bez `error_code` | `Encontrámos eventos semelhantes. Confirme se são os mesmos eventos.` | Pokaż możliwe duplikaty. Poprzednie lub kolejne pozycje w tej samej partii mogły zostać zapisane. |
| 200 | `status: "ok"`, `outcome: "added"` lub `"skipped"` | Podsumowanie liczników lub informacja, że wydarzenia są już zarejestrowane. | Pokaż wyniki zapisu, a jeśli odpowiedź zawiera `review_items`, także pozycje do korekty. |

Limit czasu lub błąd połączenia podczas analizy zwraca `503
ocr_temporarily_unavailable` dla żądań Bearer. Przy uwierzytelnieniu Google
ten przypadek trafia do zwykłego HTTP 422. Ogólne HTTP 503, przerwane
połączenie lub brak odpowiedzi wymagają sprawdzenia arkusza przed powtórzeniem
żądania. Utrzymujące się błędy modelu należy zgłosić po wyczerpaniu prób.

Komunikaty przetwarzania obrazu zaczynają się od `Image processing failed: …`.
Przykładowe szczegóły to `File size too large. Maximum size is 10MB.` oraz
`Invalid file type. Please upload an image file (JPEG, PNG, GIF, WebP, BMP, or TIFF).`

## Jak odczytać wynik zapisu i pozycje do korekty

Przy HTTP 200, 409 i `503 ingestion_failed` tablica `events` zawiera
wydarzenia przekazane do etapu zapisu. `results[].index` wskazuje pozycję
w `events`, licząc od zera. `counts` podaje liczbę `added`, `skipped`
i `conflicted`.

| `results[].status` | Znaczenie |
| --- | --- |
| `added` | Zapis potwierdzony. `range` wskazuje wiersz arkusza. |
| `skipped` | Zgodny wpis już istnieje. `existing_row` wskazuje ten wpis. |
| `conflict` | Znaleziono podobne wpisy. `candidates` zawiera dane do porównania. |
| `failed` | Operacja zakończyła się błędem. Arkusz może już zawierać wiersz, np. po utracie odpowiedzi na zapis. |
| `not_attempted` | Pozycja następuje po błędzie i nie została wysłana do zapisu. |

`review_items` zawiera pozycje wymagające korekty OCR i pojawia się tylko
wtedy, gdy są takie pozycje. Każda ma `reason`, opcjonalną treść `message`
oraz `candidate` z odczytanymi danymi lub `null`, gdy brakuje kandydata.
Przy `invalid_event_fields` pole `validation_errors` grupuje błędy według
nazwy pola, a `candidate` zachowuje odczytane wartości. Jeśli istnieją
wyłącznie pozycje do korekty, endpoint zwraca `422 ocr_review_required`.

## Komunikaty formularza podczas korekty

Formularz podstawia własną instrukcję dla trzech powodów zwracanych jako
`review_items[].reason`. Dla pozostałych pokazuje `review_items[].message`,
jeżeli odpowiedź je zawiera.

| Powód | Instrukcja w formularzu |
| --- | --- |
| `conflicting_location_evidence` | `Confirme o local do evento.` |
| `missing_start_date` | `Indique a data de início do evento.` |
| `conflicting_inset` | `Confirme a data e a hora do evento antes de submeter.` |

Przy błędach przypisanych do pól formularz wyświetla `Verifique o campo «{pole}».`
i w razie dostępności dodaje `Sugestão do OCR: {wartość}.`
[Kod formularza](../events_listing/assets/js/upload_form.js)

## Wdrożenie

Obsługę odpowiedzi łączących wyniki zapisu z pozycjami do korekty należy
wdrożyć w formularzu i kliencie Câmara przed włączeniem tego zachowania
w endpoincie. [Kod endpointu](../bin/server.rb) ·
[Reguły korekty OCR](../lib/server/ocr/admission.rb) ·
[Obsługa duplikatów](../README.md#duplicate-feedback)
