# Test data

Everything the kit sends is fictional. Do not replace it with real data.

| Item | Value | Why it is safe to use |
|---|---|---|
| Person | Viktor Marenko, born 14/03/1991 | Invented name and date |
| E-mail | `viktor.marenko@example.lu` | `example.*` domains are reserved for documentation |
| IBAN (case A) | `LU28 0019 4006 4475 0000` | Fake test IBAN for the demo. Its checksum is valid (mod-97 check), so Presidio recognises it as an IBAN. Never use a real account. |
| IBAN-shaped string (case G) | `GB00 WEST 1234 5698 7654 32` | `00` check digits make the checksum invalid on purpose, so Presidio does not accept it as an IBAN and the `filter-in` regex masks it instead |
| AWS access key (case E) | `AKIAIOSFODNN7EXAMPLE` | The example key from AWS's documentation, also used in LiteLLM's content-filter docs. It is not a real credential. |
| Lender | "Example Bank S.A." | Invented |
| Amount | EUR 18,000 | Not personal data. It must reach the model unchanged. |

## Why these values

- **The car loan sentence** is the example from the talk (slides 18-19): a name, a
  date, an IBAN and an e-mail that must be replaced, and an amount that must not.
- **Two IBANs** show the difference between the two guardrails. Presidio
  *validates* (checksum) and replaces the value reversibly. The content filter
  *matches a shape* and masks it one way.
- **The wording of contract A** avoids Presidio false positives. With the default
  English model, a capitalised "Borrower" was detected as a `PERSON`, and
  "monthly" as a `DATE_TIME`. That is fine for privacy (over-masking) but noisy on
  stage. False negatives also happen. See "Limitations" in the README.

## Where the data goes

`tap` keeps the last 20 request bodies in memory only (lost on restart).
`scripts/verify.sh` checks that none of these values appear in any service log or
in the non-weight files of the model volume.
