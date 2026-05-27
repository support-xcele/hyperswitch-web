open SuperpositionTypes

type dynamicFieldElement =
  | Card(array<fieldConfig>)
  | FullName(fieldConfig, fieldConfig)
  | Email(array<fieldConfig>)
  | Phone(fieldConfig)
  | DateOfBirth(fieldConfig)
  | StateDropdown(fieldConfig, string)
  | CountryDropdown(fieldConfig, array<DropdownField.optionType>)
  | PhoneCountryCodeDropdown(fieldConfig)
  | CryptoNetworkDropdown(fieldConfig, string)
  | GenericDropdown(fieldConfig, array<DropdownField.optionType>, string)
  | GenericInput(fieldConfig)

let elementPrimaryField = element =>
  switch element {
  | Card(fields) => fields->Array.get(0)
  | FullName(first, _) => Some(first)
  | Email(fields) => fields->Array.get(0)
  | Phone(field)
  | DateOfBirth(field)
  | StateDropdown(field, _)
  | CountryDropdown(field, _)
  | PhoneCountryCodeDropdown(field)
  | CryptoNetworkDropdown(field, _)
  | GenericDropdown(field, _, _)
  | GenericInput(field) =>
    Some(field)
  }

// Prepares dropdown options from a fieldConfig; applies ISO→country name conversion for country fields.
let prepareDropdownOptions = (field: fieldConfig): array<DropdownField.optionType> => {
  let rawOptions = field.dropdownOptions->Option.getOr([])
  if field.confirmRequestWritePath->String.endsWith(".country") {
    rawOptions
    ->Utils.isoOptionsToCountryNames
    ->DropdownField.updateArrayOfStringToOptionsTypeArray
  } else {
    rawOptions->DropdownField.updateArrayOfStringToOptionsTypeArray
  }
}

// Classifies a Dropdown field into a specific dynamicFieldElement variant based on path suffix.
let classifyDropdown = (field: fieldConfig): dynamicFieldElement => {
  let path = field.confirmRequestWritePath
  switch path {
  | _ if path->String.endsWith(".state") =>
    let countryPath = path->String.replace(".state", ".country")
    StateDropdown(field, countryPath)
  | _ if path->String.endsWith(".country") => CountryDropdown(field, prepareDropdownOptions(field))
  | _ if path->String.endsWith(".country_code") => PhoneCountryCodeDropdown(field)
  | _ if path->String.endsWith("crypto.network") =>
    let currencyPath = path->String.replace("crypto.network", "crypto.pay_currency")
    CryptoNetworkDropdown(field, currencyPath)
  | _ =>
    let options = prepareDropdownOptions(field)
    let initialValue = options->Array.get(0)->Option.map(o => o.value)->Option.getOr("")
    GenericDropdown(field, options, initialValue)
  }
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
    | _ if path->String.startsWith("payment_method_data.card.") => cardFields->Array.push(field)
    | CardHolderName => cardHolderNameFields->Array.push(field)
    | Email => emailFields->Array.push(field)
    | Phone => generics->Array.push(Phone(field))
    | Date => generics->Array.push(DateOfBirth(field))
    | Dropdown if field.dropdownOptions === None => ()
    | Dropdown => generics->Array.push(classifyDropdown(field))
    | Generic => generics->Array.push(GenericInput(field))
    }
  })

  let result: array<dynamicFieldElement> = []

  // Card
  if cardFields->Array.length > 0 {
    result->Array.push(Card(cardFields))
  }

  // FullName / Generic fallback
  let firstNameField =
    cardHolderNameFields->Array.find(field =>
      field.confirmRequestWritePath->String.endsWith(".first_name")
    )
  let lastNameField =
    cardHolderNameFields->Array.find(field =>
      field.confirmRequestWritePath->String.endsWith(".last_name")
    )
  switch (firstNameField, lastNameField) {
  | (Some(first), Some(last)) => result->Array.push(FullName(first, last))
  | (Some(first), None) => result->Array.push(GenericInput(first))
  | (None, Some(last)) => result->Array.push(GenericInput(last))
  | (None, None) => ()
  }

  // Email
  if emailFields->Array.length > 0 {
    let sorted =
      emailFields->Array.toSorted((a, b) =>
        (a.fieldDisplayOrder - b.fieldDisplayOrder)->Int.toFloat
      )
    result->Array.push(Email(sorted))
  }

  // Generics
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
let groupElementsByRow = (elements: array<dynamicFieldElement>): array<
  array<dynamicFieldElement>,
> => {
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

  | Phone(field) => <PhoneField fieldConfig=field />

  | DateOfBirth(field) => <DateOfBirth fieldConfig=field />

  | StateDropdown(field, countryPath) =>
    <StateDropdownField fieldConfig=field countryFieldPath=countryPath />

  | CountryDropdown(field, options) => <CountryDropdownField fieldConfig=field options />

  | PhoneCountryCodeDropdown(field) => <PhoneCountryCodeDropdownField fieldConfig=field />

  | CryptoNetworkDropdown(field, currencyPath) =>
    <CryptoCurrencyNetworks networkField=field currencyFieldPath=currencyPath />

  | GenericDropdown(field, options, initialValue) =>
    <GenericDropdownField fieldConfig=field options initialValue />

  | GenericInput(field) => <GenericInputField fieldConfig=field fieldRef />
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
        <div key style={flexGrow: flex->Float.toString, flexShrink: "1", flexBasis: "0%"}>
          {renderElement(element, ~fieldRef)}
        </div>
      })
      ->React.array}
    </div>
  }
}
