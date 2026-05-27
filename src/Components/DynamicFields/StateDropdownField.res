open SuperpositionTypes

@react.component
let make = (~fieldConfig: fieldConfig, ~countryFieldPath: string) => {
  let {config, localeString} = Recoil.useRecoilValueFromAtom(RecoilAtoms.configAtom)
  let {label} = DynamicFieldsUtils.resolveFieldTexts(~field=fieldConfig, ~localeObject=localeString)
  let validate = DynamicFieldsUtils.resolveValidator(~field=fieldConfig, ~localeObject=localeString)
  let defaultCountryIso = Recoil.useRecoilValueFromAtom(RecoilAtoms.userCountry)
  let countryFieldProps = ReactFinalForm.useField(countryFieldPath)
  let rffCountryIso = countryFieldProps.input.value->Option.getOr("")
  let countryIso = if rffCountryIso !== "" {
    rffCountryIso
  } else {
    defaultCountryIso
  }
  let countryDisplayName = Utils.getCountryNameFromCode(countryIso)

  let stateDisplayNames = Utils.getStateNames({
    value: countryDisplayName,
    isValid: None,
    errorString: "",
  })

  let stateOptions = stateDisplayNames->DropdownField.updateArrayOfStringToOptionsTypeArray
  let defaultStateDisplayName = stateDisplayNames->Array.get(0)->Option.getOr("")
  let defaultStateCode = Utils.getStateCodeFromStateName(defaultStateDisplayName, countryIso)
  let field = ReactFinalForm.useField(
    fieldConfig.confirmRequestWritePath,
    ~config={validate: validate, initialValue: Some(defaultStateCode)},
  )
  let storedCode = field.input.value->Option.getOr("")

  React.useEffect(() => {
    field.input.onChange(defaultStateCode)
    None
  }, [countryIso])

  if stateOptions->Array.length === 0 {
    React.null
  } else {
    let displayName = Utils.getStateNameFromCode(storedCode, countryIso)
    let effectiveDisplayName =
      displayName !== "" ? displayName : defaultStateDisplayName

    <DropdownField
      appearance={config.appearance}
      fieldName={label}
      value={effectiveDisplayName}
      setValue={fn => {
        let selectedDisplayName = fn(effectiveDisplayName)
        let stateCode = Utils.getStateCodeFromStateName(selectedDisplayName, countryIso)
        field.input.onChange(stateCode)
      }}
      disabled=false
      options={stateOptions}
    />
  }
}
