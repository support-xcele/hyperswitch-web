open SuperpositionTypes

type dynamicFieldElement =
  | Card(array<fieldConfig>)
  | FullName(fieldConfig, fieldConfig)
  | Email(array<fieldConfig>)
  | Generic(fieldConfig)

let elementPrimaryField = element =>
  switch element {
  | Card(fields) => fields->Array.get(0)
  | FullName(first, _) => Some(first)
  | Email(fields) => fields->Array.get(0)
  | Generic(field) => Some(field)
  }

let categorizeDynamicFields = (fields: array<fieldConfig>): array<dynamicFieldElement> => {
  let cardFields = []
  let cardHolderNameFields = []
  let emailFields = []
  let generics = []

  fields->Array.forEach(field => {
    let path = field.confirmRequestWritePath
    switch field.fieldRenderType {
    | CardNumber | Cvc => cardFields->Array.push(field)
    | _ when path->String.startsWith("payment_method_data.card.") => cardFields->Array.push(field)
    | CardHolderName => cardHolderNameFields->Array.push(field)
    | Email => emailFields->Array.push(field)
    | Dropdown when field.dropdownOptions === None => ()
    | _ => generics->Array.push(Generic(field))
    }
  })

  let result: array<dynamicFieldElement> = []

  // Card
  if cardFields->Array.length > 0 {
    result->Array.push(Card(cardFields))
  }

  // FullName / Generic fallback
  let firstNameField = cardHolderNameFields->Array.find(field =>
    field.confirmRequestWritePath->String.endsWith(".first_name")
  )
  let lastNameField = cardHolderNameFields->Array.find(field =>
    field.confirmRequestWritePath->String.endsWith(".last_name")
  )
  switch (firstNameField, lastNameField) {
  | (Some(first), Some(last)) => result->Array.push(FullName(first, last))
  | (Some(first), None) => result->Array.push(Generic(first))
  | (None, Some(last)) => result->Array.push(Generic(last))
  | (None, None) => ()
  }

  // Email
  if emailFields->Array.length > 0 {
    let sorted =
      emailFields->Array.toSorted((a, b) => (a.fieldDisplayOrder - b.fieldDisplayOrder)->Int.toFloat)
    result->Array.push(Email(sorted))
  }

  // Generics (already constructed as Generic(...))
  generics->Array.forEach(element => result->Array.push(element))

  // Sort all by fieldDisplayOrder of primary field
  result->Array.toSorted((a, b) => {
    let orderA =
      elementPrimaryField(a)->Option.map(field => field.fieldDisplayOrder)->Option.getOr(999)
    let orderB =
      elementPrimaryField(b)->Option.map(field => field.fieldDisplayOrder)->Option.getOr(999)
    (orderA - orderB)->Int.toFloat
  })
}

// Groups an array of dynamicFieldElement by layoutRowId of the primary field.
// Elements with no layoutRowId each form their own singleton row.
let groupElementsByRow = (elements: array<dynamicFieldElement>): array<array<dynamicFieldElement>> => {
  let rows: array<array<dynamicFieldElement>> = []
  let rowMap: Dict.t<array<dynamicFieldElement>> = Dict.make()

  // Card elements handled in CardPayment.res 
  let renderableElements = elements->Array.filter(element =>
    switch element {
    | Card(_) => false
    | _ => true
    }
  )

  renderableElements->Array.forEach(element => {
    let rowId = elementPrimaryField(element)->Option.flatMap(field => field.layoutRowId)
    switch rowId {
    | None => rows->Array.push([element])
    | Some(id) =>
      switch rowMap->Dict.get(id) {
      | Some(row) => row->Array.push(element)
      | None =>
        let row = [element]
        rowMap->Dict.set(id, row)
        rows->Array.push(row)
      }
    }
  })

  rows
}

// Renders a single dynamicFieldElement as a RFF-connected input.
let renderElement = (element: dynamicFieldElement, ~fieldRef: React.ref<Nullable.t<'a>>) => {
  switch element {
  | Card(_) => React.null

  | FullName(first, last) => <CardHolderNameField firstNameField=first lastNameField=last />

  | Email(fields) =>
    let paths = fields->Array.map(f => f.confirmRequestWritePath)
    <EmailField fieldConfig={fields->Array.getUnsafe(0)} paths />

  | Generic(field) =>
    switch field.fieldRenderType {
    | Phone => <PhoneField fieldConfig=field />

    | Date => <DateOfBirth fieldConfig=field />

    | Dropdown =>
      if field.confirmRequestWritePath->String.endsWith(".state") {
        let countryFieldPath =
          field.confirmRequestWritePath->String.replace(".state", ".country")
        <StateDropdownField fieldConfig=field countryFieldPath />
      } else if field.confirmRequestWritePath->String.endsWith(".country") {
        let isoCodes = field.dropdownOptions->Option.getOr([])
        let options =
          isoCodes
          ->Utils.isoOptionsToCountryNames
          ->DropdownField.updateArrayOfStringToOptionsTypeArray
        <CountryDropdownField fieldConfig=field options />
      } else if field.confirmRequestWritePath->String.endsWith(".country_code") {
        <PhoneCountryCodeDropdownField fieldConfig=field />
      } else if field.confirmRequestWritePath->String.endsWith("crypto.network") {
        let currencyPath =
          field.confirmRequestWritePath->String.replace("crypto.network", "crypto.pay_currency")
        <CryptoCurrencyNetworks networkField=field currencyFieldPath=currencyPath />
      } else {
        let options =
          field.dropdownOptions
          ->Option.getOr([])
          ->DropdownField.updateArrayOfStringToOptionsTypeArray
        let initialValue =
          options->Array.get(0)->Option.map(o => o.value)->Option.getOr("")
        <GenericDropdownField fieldConfig=field options initialValue />
      }

    | CardNumber | Cvc | CardHolderName | Email => React.null // safety net — handled by dedicated elements

    | Generic =>
      let {localeString} = Recoil.useRecoilValueFromAtom(RecoilAtoms.configAtom)
      let {label, placeholder} = DynamicFieldsUtils.resolveFieldTexts(
        ~field,
        ~localeObject=localeString,
      )
      let autocomplete = field.htmlAutocompleteAttribute->Option.getOr("on")
      let validate = DynamicFieldsUtils.resolveValidator(~field, ~localeObject=localeString)
      <ReactFinalForm.Field name={field.confirmRequestWritePath} validate={Some(validate)}>
        {(fieldProps: ReactFinalForm.Field.fieldProps) => {
          let {input, meta} = fieldProps
          let value = input.value->Option.getOr("")
          let isValid = if meta.touched {
            Some(meta.valid)
          } else {
            None
          }
          let errorString = if meta.touched && meta.invalid {
            meta.error->Option.getOr("")
          } else {
            ""
          }
          <PaymentInputField
            fieldName={label}
            value
            onChange={ev => input.onChange(ReactEvent.Form.target(ev)["value"])}
            onBlur={_ev => input.onBlur()}
            isValid
            errorString
            placeholder
            inputRef={fieldRef}
            autocomplete
            maxLength=?{field.maxInputLength}
          />
        }}
      </ReactFinalForm.Field>
    }
  }
}

// Renders a row of dynamicFieldElements side-by-side using flex layout.
@react.component
let makeRow = (~fields: array<dynamicFieldElement>) => {
  let fieldRef = React.useRef(Nullable.null)

  switch fields->Array.length {
  | 0 => React.null
  | 1 =>
    switch fields->Array.get(0) {
    | None => React.null
    | Some(element) => renderElement(element, ~fieldRef)
    }
  | _ =>
    <div className="flex gap-4 w-full">
      {fields
      ->Array.mapWithIndex((element, i) => {
        let flex =
          elementPrimaryField(element)
          ->Option.flatMap(field => field.layoutWidthRatio)
          ->Option.getOr(1.0)
        let key =
          elementPrimaryField(element)
          ->Option.map(field => field.confirmRequestWritePath)
          ->Option.getOr(i->Int.toString) ++
          "-" ++
          i->Int.toString
        <div
          key
          style={flexGrow: flex->Float.toString, flexShrink: "1", flexBasis: "0%"}>
          {renderElement(element, ~fieldRef)}
        </div>
      })
      ->React.array}
    </div>
  }
}
