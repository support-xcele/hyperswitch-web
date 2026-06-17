type optionType = {
  value: string,
  label?: string,
  displayValue?: string,
  flagUrl?: string,
  // Extra lowercase search text (name + ISO codes + aliases) for searchable mode.
  keywords?: string,
}

let updateArrayOfStringToOptionsTypeArrayWithUpperCaseLabel = arrayOfString =>
  arrayOfString->Array.map(item => {
    value: item,
    label: item->String.toUpperCase,
  })

let updateArrayOfStringToOptionsTypeArray = arrayOfString =>
  arrayOfString->Array.map(item => {
    value: item,
  })

let defaultValue = {
  value: "",
}

open RecoilAtoms
@react.component
let make = (
  ~appearance: CardThemeType.appearance,
  ~value,
  ~setValue,
  ~isDisplayValueVisible=false,
  ~displayValue=?,
  ~setDisplayValue=?,
  ~fieldName,
  ~options: array<optionType>,
  ~disabled=false,
  ~className="",
  ~width="w-full",
  ~leadingFlagUrl=?,
  ~searchable=false,
) => {
  let {themeObj, localeString, config} = Recoil.useRecoilValueFromAtom(configAtom)
  let {readOnly} = Recoil.useRecoilValueFromAtom(optionAtom)
  let loggerState = Recoil.useRecoilValueFromAtom(loggerAtom)
  let dropdownRef = React.useRef(Nullable.null)
  let (inputFocused, setInputFocused) = React.useState(_ => false)
  let {parentURL} = Recoil.useRecoilValueFromAtom(keys)
  let isSpacedInnerLayout = config.appearance.innerLayout === Spaced
  // Custom searchable-combobox state (only used when ~searchable=true, e.g. the
  // billing Country field — the native <select> popup can't show a search box,
  // flags, or glass styling).
  let (isOpen, setIsOpen) = React.useState(_ => false)
  let (query, setQuery) = React.useState(_ => "")

  let handleFocus = _ => {
    setInputFocused(_ => true)
    Utils.handleOnFocusPostMessage(~targetOrigin=parentURL)
  }

  let handleChange = ev => {
    let target = ev->ReactEvent.Form.target
    let value = target["value"]

    // Log the dropdown change using fieldName
    if fieldName->String.length > 0 {
      LoggerUtils.logInputChangeInfo(fieldName, loggerState)
    }
    setValue(_ => value)
    if isDisplayValueVisible {
      let findDisplayValue =
        options
        ->Array.find(ele => ele.value === value)
        ->Option.getOr(defaultValue)

      switch setDisplayValue {
      | Some(setDisplayValue) =>
        setDisplayValue(_ => findDisplayValue.displayValue->Option.getOr(value))
      | None => ()
      }
    }
  }
  let disbaledBG = React.useMemo(() => {
    themeObj.colorBackground
  }, [themeObj])
  React.useEffect0(() => {
    if value === "" || !(options->Array.map(val => val.value)->Array.includes(value)) {
      setValue(_ =>
        (
          options
          ->Array.get(0)
          ->Option.getOr(defaultValue)
        ).value
      )
    }
    None
  })

  let focusClass = if inputFocused || value->String.length > 0 {
    `mb-7 pb-1 pt-2 ${themeObj.fontSizeXs} transition-all ease-in duration-75`
  } else {
    "transition-all ease-in duration-75"
  }

  let floatinglabelClass = inputFocused ? "Label--floating" : "Label--resting"
  let inputClassStyles = isSpacedInnerLayout ? "Input" : "Input-Compressed"

  let cursorClass = !disabled ? "cursor-pointer" : "cursor-not-allowed"
  // ── Searchable combobox derived values (used only when ~searchable=true) ──
  let selectedOpt = options->Array.find(o => o.value === value)
  let selectedLabel = switch selectedOpt {
  | Some(o) => o.label->Option.getOr(o.value)
  | None => value
  }
  let selectedFlag = selectedOpt->Option.flatMap(o => o.flagUrl)
  let normalizedQuery = query->String.trim->String.toLowerCase
  let optionNameText = o => (o.label->Option.getOr(o.value))->String.toLowerCase
  // Search against keywords (name + ISO codes + aliases like "america"/"usa")
  // when present, else just the visible name.
  let optionSearchText = o =>
    switch o.keywords {
    | Some(k) => k
    | None => optionNameText(o)
    }
  let filteredOptions =
    if normalizedQuery === "" {
      options
    } else {
      let matched = options->Array.filter(o => optionSearchText(o)->String.includes(normalizedQuery))
      // Rank names that START with the query above mere substring/alias matches.
      let prefix = matched->Array.filter(o => optionNameText(o)->String.startsWith(normalizedQuery))
      let rest = matched->Array.filter(o => !(optionNameText(o)->String.startsWith(normalizedQuery)))
      Array.concat(prefix, rest)
    }
  let selectCountry = v => {
    if fieldName->String.length > 0 {
      LoggerUtils.logInputChangeInfo(fieldName, loggerState)
    }
    setValue(_ => v)
    setIsOpen(_ => false)
    setQuery(_ => "")
  }
  <RenderIf condition={options->Array.length > 0}>
    {searchable
      ? <div className={`flex flex-col ${width} relative`}>
          <RenderIf
            condition={fieldName->String.length > 0 &&
            appearance.labels == Above &&
            isSpacedInnerLayout}>
            <div
              className={`Label `}
              style={
                fontWeight: themeObj.fontWeightNormal,
                fontSize: themeObj.fontSizeLg,
                marginBottom: "5px",
                opacity: "0.6",
              }
              ariaHidden=true>
              {React.string(fieldName)}
            </div>
          </RenderIf>
          <div className="relative" style={zIndex: isOpen ? "50" : "auto"}>
            <button
              type_="button"
              disabled={readOnly || disabled}
              onClick={_ => setIsOpen(p => !p)}
              className={`${inputClassStyles} ${className} w-full flex items-center outline-none ${cursorClass}`}
              style={
                background: disabled ? disbaledBG : themeObj.colorBackground,
                opacity: disabled ? "35%" : "",
                padding: themeObj.spacingUnit,
                color: themeObj.colorText,
                width: "100%",
                textAlign: "left",
              }>
              {switch selectedFlag {
              | Some(url) =>
                <img
                  src=url
                  alt=""
                  className="rounded-sm flex-shrink-0"
                  style={width: "22px", height: "16px", marginRight: "8px"}
                />
              | None => React.null
              }}
              <span className="truncate flex-1 min-w-0"> {React.string(selectedLabel)} </span>
              <span className="ml-2 flex-shrink-0" style={opacity: "0.55", color: themeObj.colorText}>
                <Icon size=10 name={"arrow-down"} />
              </span>
            </button>
            <RenderIf condition={isOpen}>
              <div
                className="rounded-xl overflow-hidden"
                style={
                  // Open UPWARD (above the trigger): the Country field sits low in
                  // the form, and on mobile a downward panel is hidden behind the
                  // fixed Pay button + keyboard. Plenty of fields above => no clip.
                  position: "absolute",
                  bottom: "calc(100% + 6px)",
                  left: "0",
                  right: "0",
                  zIndex: "50",
                  border: "1px solid rgba(255,255,255,0.14)",
                  background: "rgba(16,18,26,0.96)",
                  boxShadow: "0 -18px 55px rgba(0,0,0,0.5)",
                }>
                <input
                  type_="text"
                  value={query}
                  placeholder="Search"
                  autoFocus=true
                  onChange={ev => {
                    let v = (ev->ReactEvent.Form.target)["value"]
                    setQuery(_ => v)
                  }}
                  onKeyDown={ev =>
                    if (ev->ReactEvent.Keyboard.key) === "Escape" {
                      setIsOpen(_ => false)
                    }}
                  className="outline-none block"
                  style={
                    margin: "8px",
                    padding: "11px 13px",
                    background: "rgba(255,255,255,0.06)",
                    border: "1px solid rgba(255,255,255,0.18)",
                    borderRadius: "10px",
                    color: "#ffffff",
                    fontSize: themeObj.fontSizeLg,
                    width: "calc(100% - 16px)",
                  }
                />
                <div className="overflow-y-auto" style={maxHeight: "240px", padding: "0 6px 8px"}>
                  {filteredOptions
                  ->Array.mapWithIndex((item, index) =>
                    <div
                      key={Int.toString(index)}
                      className="flex items-center rounded-lg cursor-pointer"
                      onClick={_ => selectCountry(item.value)}
                      style={padding: "11px 10px", color: "rgba(255,255,255,0.9)"}>
                      {switch item.flagUrl {
                      | Some(url) =>
                        <img
                          src=url
                          alt=""
                          className="rounded-sm flex-shrink-0"
                          style={width: "22px", height: "16px", marginRight: "9px"}
                        />
                      | None => React.null
                      }}
                      {React.string(item.label->Option.getOr(item.value))}
                    </div>
                  )
                  ->React.array}
                </div>
              </div>
            </RenderIf>
          </div>
          <RenderIf condition={isOpen}>
            <div className="fixed inset-0" style={zIndex: "40"} onClick={_ => setIsOpen(_ => false)} />
          </RenderIf>
        </div>
      : <div className={`flex flex-col ${width}`}>
      <RenderIf
        condition={fieldName->String.length > 0 &&
        appearance.labels == Above &&
        isSpacedInnerLayout}>
        <div
          className={`Label `}
          style={
            fontWeight: themeObj.fontWeightNormal,
            fontSize: themeObj.fontSizeLg,
            marginBottom: "5px",
            opacity: "0.6",
          }
          ariaHidden=true>
          {React.string(fieldName)}
        </div>
      </RenderIf>
      <div className="relative">
        {switch leadingFlagUrl {
        | Some(url) =>
          <img
            src=url
            alt=""
            className="absolute z-20 pointer-events-none"
            style={
              left: "12px",
              top: "calc(50% - 8px)",
              width: "22px",
              height: "16px",
              borderRadius: "3px",
            }
          />
        | None => React.null
        }}
        <RenderIf condition={isDisplayValueVisible && displayValue->Option.isSome}>
          <div
            className="absolute top-[2px] left-[2px] right-0 bottom-[2px]  pointer-events-none rounded-sm z-20 whitespace-nowrap"
            style={
              background: disabled ? disbaledBG : themeObj.colorBackground,
              opacity: disabled ? "35%" : "",
              padding: themeObj.spacingUnit,
              width: "calc(100% - 22px)",
            }
            ariaHidden=true>
            {React.string(displayValue->Option.getOr(""))}
          </div>
        </RenderIf>
        <select
          ref={dropdownRef->ReactDOM.Ref.domRef}
          style={
            background: disabled ? disbaledBG : themeObj.colorBackground,
            opacity: disabled ? "35%" : "",
            padding: themeObj.spacingUnit,
            paddingRight: "22px",
            paddingLeft: {leadingFlagUrl->Option.isSome ? "42px" : ""},
            width: "100%",
          }
          name=""
          value
          disabled={readOnly || disabled}
          onChange=handleChange
          onFocus=handleFocus
          className={`${inputClassStyles} ${className} w-full appearance-none outline-none overflow-hidden whitespace-nowrap text-ellipsis ${cursorClass}`}
          ariaLabel={`${fieldName} option tab`}>
          {options
          ->Array.mapWithIndex((item, index) => {
            <option key={Int.toString(index)} value=item.value>
              {React.string(item.label->Option.getOr(item.value))}
            </option>
          })
          ->React.array}
        </select>
        <RenderIf condition={config.appearance.labels == Floating}>
          <div
            className={`Label ${floatinglabelClass} absolute bottom-0 ml-3 ${focusClass} pointer-events-none`}
            style={
              marginBottom: {
                inputFocused || value->String.length > 0 ? "" : themeObj.spacingUnit
              },
              fontSize: {
                inputFocused || value->String.length > 0 ? themeObj.fontSizeXs : ""
              },
              opacity: "0.6",
            }
            ariaHidden=true>
            {React.string(fieldName)}
          </div>
        </RenderIf>
        <div
          className="self-center absolute pointer-events-none"
          style={
            opacity: disabled ? "35%" : "",
            color: themeObj.colorText,
            left: localeString.localeDirection == "rtl" ? "1%" : "97%",
            top: "42%",
            marginLeft: localeString.localeDirection == "rtl" ? "1rem" : "-1rem",
          }>
          <Icon size=10 name={"arrow-down"} />
        </div>
      </div>
    </div>}
  </RenderIf>
}
