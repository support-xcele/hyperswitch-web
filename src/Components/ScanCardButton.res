// "Scan card" button for the getmypics glass checkout.
//
// Lives inside the unified Payment Element card form. On tap it runs the
// configured on-device card scanner (CardScan.scanCard) — Microblink WASM or
// tesseract.js, picked by GlobalVars.cardScanEngine — and hands the extracted
// number / expiry / name to `onScanned`, which fills the card fields. CVC is
// intentionally NOT scanned — the buyer always types it.
//
// Rendered only when a card-scan engine was selected at build time (see the
// RenderIf gate at the call site), so with no engine the checkout is unchanged.

@react.component
let make = (
  ~onScanned: (~number: string, ~expiryMonth: int, ~expiryYear: int, ~name: string) => unit,
) => {
  let {themeObj} = Recoil.useRecoilValueFromAtom(RecoilAtoms.configAtom)
  let (scanning, setScanning) = React.useState(_ => false)
  let (errorMsg, setErrorMsg) = React.useState(_ => "")

  // The WASM engine + worker are served next to HyperLoader.js (copied there by
  // copy-webpack-plugin). engineLocation resolves to .../web/<ver>/<v>/resources.
  let engineLocation = GlobalVars.sdkUrl ++ GlobalVars.repoPublicPath ++ "/resources"

  let handleClick = _ev =>
    if !scanning {
      setErrorMsg(_ => "")
      setScanning(_ => true)
      CardScan.scanCard(GlobalVars.cardScanEngine, GlobalVars.microblinkLicenseKey, engineLocation)
      ->Promise.thenResolve(result => {
        switch result->Nullable.toOption {
        | Some(r) =>
          onScanned(~number=r.number, ~expiryMonth=r.expiryMonth, ~expiryYear=r.expiryYear, ~name=r.name)
        | None => setErrorMsg(_ => "Couldn't read the card — try again in better light.")
        }
        setScanning(_ => false)
      })
      ->Promise.catch(_err => {
        setScanning(_ => false)
        setErrorMsg(_ => "Card scan isn't available here — please type your details.")
        Promise.resolve()
      })
      ->ignore
    }

  <div className="flex flex-col w-full">
    <button
      type_="button"
      ariaLabel="Scan your card with the camera"
      disabled={scanning}
      onClick={handleClick}
      className="ScanCardButton flex flex-row items-center justify-center w-full cursor-pointer"
      style={ReactDOM.Style.make(
        ~gap="8px",
        ~marginBottom="10px",
        ~padding="12px 14px",
        ~borderRadius="14px",
        ~border="1px solid rgba(255,255,255,0.22)",
        ~backgroundColor="rgba(255,255,255,0.06)",
        ~color="#ffffff",
        ~fontSize="14px",
        ~fontWeight="500",
        ~opacity={scanning ? "0.6" : "1"},
        (),
      )}>
      <svg
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg">
        <path
          d="M3 8.5A2.5 2.5 0 0 1 5.5 6h1.2a1 1 0 0 0 .83-.45l.74-1.1A1 1 0 0 1 9.1 4h5.8a1 1 0 0 1 .83.45l.74 1.1a1 1 0 0 0 .83.45h1.2A2.5 2.5 0 0 1 21 8.5v8A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5v-8Z"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinejoin="round"
        />
        <path
          d="M15.2 12a3.2 3.2 0 1 1-6.4 0 3.2 3.2 0 0 1 6.4 0Z"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinejoin="round"
        />
      </svg>
      {React.string(scanning ? "Scanning…" : "Scan card")}
    </button>
    <RenderIf condition={errorMsg->String.length > 0}>
      <div
        className="pb-2"
        style={ReactDOM.Style.make(
          ~color=themeObj.colorDangerText,
          ~fontSize=themeObj.fontSizeSm,
          ~textAlign="left",
          (),
        )}>
        {React.string(errorMsg)}
      </div>
    </RenderIf>
  </div>
}
