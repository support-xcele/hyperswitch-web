// Card-scan shim for the getmypics glass checkout.
//
// Exposes a single `scanCard(engine, licenseKey, engineLocation)` that: opens
// the device camera / photo picker, reads ONE still photo of the front of the
// card, and returns the extracted number / expiry / cardholder name. Two OCR
// engines are supported, picked by the build flag `engine`:
//
//   "microblink" — @microblink/blinkcard-in-browser-sdk (on-device WASM OCR).
//                  Needs an FQDN-locked license key. The card image and PAN
//                  never leave the browser — recognition runs entirely in WASM.
//   "tesseract"  — tesseract.js (free, on-device OCR). No license needed. The
//                  card IMAGE never leaves the device; only the OCR engine +
//                  language model are fetched from the CDN.
//
// Each engine is loaded via a dynamic import() so webpack splits it into its
// own chunk fetched only the first time a buyer taps Scan.
//
// NOTE: @microblink/blinkcard-in-browser-sdk@2.x is deprecated upstream in
// favour of @microblink/blinkcard. We pin 2.x because its API is stable and
// fully documented; migrating is a self-contained follow-up.

let sdkPromise = null;

// Load + initialise the WASM engine once, then reuse it for subsequent scans.
function loadSdk(licenseKey, engineLocation) {
  if (!sdkPromise) {
    sdkPromise = (async () => {
      const BlinkCardSDK = await import(
        /* webpackChunkName: "blinkcard" */ "@microblink/blinkcard-in-browser-sdk"
      );
      if (!BlinkCardSDK.isBrowserSupported()) {
        throw new Error("blinkcard-unsupported");
      }
      const settings = new BlinkCardSDK.WasmSDKLoadSettings(licenseKey);
      settings.engineLocation = engineLocation;
      settings.allowHelloMessage = false;
      const wasmSDK = await BlinkCardSDK.loadWasmModule(settings);
      return { BlinkCardSDK, wasmSDK };
    })().catch((err) => {
      // Allow a later retry (e.g. transient network / a fixed license key).
      sdkPromise = null;
      throw err;
    });
  }
  return sdkPromise;
}

function readAsDataURL(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error || new Error("file-read-failed"));
    reader.readAsDataURL(file);
  });
}

// Recognise a single still photo with Microblink BlinkCard WASM OCR.
// (the card front carries PAN + expiry + name).
async function recognizeMicroblink(dataUrl, licenseKey, engineLocation) {
  const { BlinkCardSDK, wasmSDK } = await loadSdk(licenseKey, engineLocation);
  const recognizer = await BlinkCardSDK.createBlinkCardRecognizer(wasmSDK);
  const runner = await BlinkCardSDK.createRecognizerRunner(wasmSDK, [recognizer], false);
  let img = null;
  try {
    // data: URL (not blob:) so we don't need `blob:` in the iframe CSP img-src.
    img = document.createElement("img");
    img.src = dataUrl;
    await img.decode();

    const frame = BlinkCardSDK.captureFrame(img);
    const state = await runner.processImage(frame);
    if (state === BlinkCardSDK.RecognizerResultState.Empty) {
      return null;
    }

    const result = await recognizer.getResult();
    const number = (result.cardNumber || "").replace(/\D/g, "");
    if (!number) {
      return null;
    }
    const expiry = result.expiryDate || {};
    return {
      number,
      expiryMonth: typeof expiry.month === "number" ? expiry.month : 0,
      expiryYear: typeof expiry.year === "number" ? expiry.year : 0,
      name: result.owner || result.cardholderName || "",
    };
  } finally {
    try { runner.delete(); } catch (_e) { /* noop */ }
    try { recognizer.delete(); } catch (_e) { /* noop */ }
    if (img) { img.src = ""; }
  }
}

// Luhn (mod-10) checksum used to pick the real PAN out of the OCR text noise.
// NOTE: ReScript's `mod` is unrelated here — this is plain JS.
function luhn(digits) {
  let sum = 0;
  let alt = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48; // '0' === 48
    if (d < 0 || d > 9) return false;
    if (alt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    alt = !alt;
  }
  return digits.length > 0 && sum % 10 === 0;
}

// Recognise a single still photo with tesseract.js (free, on-device OCR).
//
// PRIVACY: the card image NEVER leaves the device — only the OCR engine (WASM)
// and the English language model are loaded from the CDN. We restrict the
// character set to digits + space + slash to keep the PAN/expiry read clean.
async function recognizeTesseract(dataUrl) {
  // Lazy import => tesseract.js lands in its own webpack chunk fetched on first scan.
  const Tesseract = await import(/* webpackChunkName: "tesseract" */ "tesseract.js");
  // Top-level recognize() manages (and tears down) its own worker for us.
  const { data } = await Tesseract.recognize(dataUrl, "eng", {
    tessedit_char_whitelist: "0123456789 /",
  });

  const text = (data && data.text) || "";
  const lines = text.split(/\r?\n/);

  // Candidate PAN: the longest Luhn-valid run of 13-19 digits found on any line
  // after stripping spaces (card numbers are printed in space-separated groups).
  let bestNumber = "";
  for (const line of lines) {
    const stripped = line.replace(/\s+/g, "");
    const runs = stripped.match(/\d{13,19}/g);
    if (!runs) continue;
    for (const run of runs) {
      if (luhn(run) && run.length > bestNumber.length) {
        bestNumber = run;
      }
    }
  }
  if (!bestNumber) {
    return null;
  }

  // Expiry: first MM/YY (or "MM YY") match anywhere in the OCR text.
  let expiryMonth = 0;
  let expiryYear = 0;
  const expMatch = text.match(/\b(0[1-9]|1[0-2])\s*\/?\s*(\d{2})\b/);
  if (expMatch) {
    expiryMonth = parseInt(expMatch[1], 10);
    expiryYear = 2000 + parseInt(expMatch[2], 10);
  }

  return { number: bestNumber, expiryMonth, expiryYear, name: "" };
}

// Dispatch to the configured OCR engine for one captured still photo.
async function recognizeFile(file, engine, licenseKey, engineLocation) {
  // Read the photo to a data: URL once, then hand it to whichever engine is on.
  const dataUrl = await readAsDataURL(file);
  if (engine === "tesseract") {
    return recognizeTesseract(dataUrl);
  }
  // Default / "microblink": the original WASM BlinkCard path, unchanged.
  return recognizeMicroblink(dataUrl, licenseKey, engineLocation);
}

// Public entry point called from ReScript. Resolves to a result object, or null
// if the buyer cancelled / no card could be read. Rejects only on a hard engine
// failure (license/engine/browser-unsupported) so the UI can fall back to
// manual entry. Must be invoked from a user gesture (the button onClick) — the
// file input is created and clicked synchronously to preserve that gesture.
// `engine` selects the OCR backend: "microblink" | "tesseract".
export function scanCard(engine, licenseKey, engineLocation) {
  return new Promise((resolve, reject) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    input.setAttribute("capture", "environment");
    input.style.position = "fixed";
    input.style.left = "-9999px";

    let done = false;
    const teardown = () => {
      window.removeEventListener("focus", onWindowFocus);
      if (input.parentNode) {
        input.parentNode.removeChild(input);
      }
    };
    // Fallback for the "picker cancelled" case: no reliable cross-browser cancel
    // event, so when the window regains focus and no file was chosen, resolve null.
    const onWindowFocus = () => {
      setTimeout(() => {
        if (done) return;
        if (!input.files || input.files.length === 0) {
          done = true;
          teardown();
          resolve(null);
        }
      }, 600);
    };

    input.onchange = () => {
      if (done) return;
      const file = input.files && input.files[0];
      done = true;
      teardown();
      if (!file) {
        resolve(null);
        return;
      }
      recognizeFile(file, engine, licenseKey, engineLocation).then(resolve, reject);
    };

    window.addEventListener("focus", onWindowFocus);
    document.body.appendChild(input);
    input.click();
  });
}
