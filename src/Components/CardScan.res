// ReScript binding to the BlinkCard scan shim (./CardScanShim.js).
//
// `scanCard(engine, licenseKey, engineLocation)` opens the camera / photo
// picker, runs on-device OCR (engine = "microblink" | "tesseract") on one still
// photo, and resolves to the extracted card details — or Null if the buyer
// cancelled / no card could be read. It rejects only on a hard engine failure
// so the caller can fall back to manual entry.

type scanResult = {
  number: string,
  expiryMonth: int,
  expiryYear: int,
  name: string,
}

@module("./CardScanShim.js")
external scanCard: (string, string, string) => promise<Nullable.t<scanResult>> = "scanCard"
