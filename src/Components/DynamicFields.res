module DynamicFieldsToRenderWrapper = {
  @react.component
  let make = (~children, ~index, ~isInside=true) => {
    let {themeObj} = Recoil.useRecoilValueFromAtom(RecoilAtoms.configAtom)

    <RenderIf condition={children != React.null}>
      <div
        key={`${isInside ? "inside" : "outside"}-billing-${index->Int.toString}`}
        className="flex flex-col w-full place-content-between"
        style={
          gridColumnGap: isInside ? "0px" : themeObj.spacingGridRow,
        }>
        {children}
      </div>
    </RenderIf>
  }
}

@react.component
let make = (
  ~paymentMethod,
  ~paymentMethodType,
  ~setRequiredFieldsBody,
  ~isSavedCardFlow=false,
  ~savedMethod=PaymentType.defaultCustomerMethods,
  ~cardProps=None,
  ~expiryProps=None,
  ~cvcProps=None,
  ~isBancontact=false,
  ~isSaveDetailsWithClickToPay=false,
  ~isDisableInfoElement=false,
  ~isSplitPaymentsEnabled=false,
) => {
  open DynamicFieldsUtils
  open Utils
  open RecoilAtoms
  open SuperpositionTypes

  let paymentMethodListValue = Recoil.useRecoilValueFromAtom(PaymentUtils.paymentMethodListValue)
  let {config, themeObj, localeString} = Recoil.useRecoilValueFromAtom(configAtom)
  let {billingAddress, redirectionInfo} = Recoil.useRecoilValueFromAtom(optionAtom)
  let country = Recoil.useRecoilValueFromAtom(userCountry)
  let sdkConfigs = Recoil.useRecoilValueFromAtom(sdkConfigs)

  React.useEffect(() => {
    setRequiredFieldsBody(_ => Dict.make())
    None
  }, [paymentMethodType])

  let paymentMethodTypes = PaymentUtils.usePaymentMethodTypeFromList(
    ~paymentMethodListValue,
    ~paymentMethod,
    ~paymentMethodType,
  )

  let rawConfigs = React.useMemo(() => {
    switch sdkConfigs {
    | Loaded(json) => json->getDictFromJson->Dict.get("raw_configs")
    | _ => None
    }
  }, [sdkConfigs])

  let getSuperpositionFinalFields = ConfigurationService.useConfigurationService(
    ~rawConfigs
  )

  let requiredFieldsFromPMLFlat = React.useMemo(() => {
    extractValuesFromPMLRequiredFields(paymentMethodTypes.required_fields)
  }, [paymentMethodTypes.required_fields])

  let eligibleConnectors = React.useMemo(() => {
    getEligibleConnectors(paymentMethodTypes, paymentMethod)
  }, (paymentMethodTypes, paymentMethod))

  let superpositionBaseContext = React.useMemo(() => {
    buildSuperpositionBaseContext(
      ~paymentMethod,
      ~paymentMethodType,
      ~country,
      ~paymentMethodListValue,
    )
  }, (paymentMethod, paymentMethodType, country, paymentMethodListValue))

  let (_requiredFields, missingRequiredFields, initialValues) = React.useMemo(() => {
    getSuperpositionFinalFields(
      eligibleConnectors,
      superpositionBaseContext,
      requiredFieldsFromPMLFlat,
    )
  }, (
    getSuperpositionFinalFields,
    eligibleConnectors,
    superpositionBaseContext,
    requiredFieldsFromPMLFlat,
  ))

  let missingRequiredFieldsFiltered = React.useMemo(() => {
    missingRequiredFields->removeBillingDetailsIfUseBillingAddress(billingAddress)
  }, (missingRequiredFields, billingAddress.isUseBillingAddress))

  let billingPrefix = "payment_method_data.billing."

  let elementsOutsideBilling = React.useMemo(() => {
    missingRequiredFieldsFiltered
    ->Array.filter(field =>
      (!(field.confirmRequestWritePath->String.startsWith(billingPrefix)) ||
      field.fieldRenderType === CardHolderName) && field.fieldRenderType !== Email
    )
    ->DynamicFieldInput.categorizeDynamicFields
  }, [missingRequiredFieldsFiltered])

  let elementsInsideBilling = React.useMemo(() => {
    missingRequiredFieldsFiltered
    ->Array.filter(field =>
      (field.confirmRequestWritePath->String.startsWith(billingPrefix) &&
        field.fieldRenderType !== CardHolderName) || field.fieldRenderType === Email
    )
    ->DynamicFieldInput.categorizeDynamicFields
  }, [missingRequiredFieldsFiltered])

  let formRef: React.ref<option<ReactFinalForm.Form.formMethods>> = React.useRef(None)

  let submitCallback = React.useCallback((ev: Window.event) => {
    let json = ev.data->safeParse
    let confirm = json->getDictFromJson->ConfirmType.itemToObjMapper
    if confirm.doSubmit {
      formRef.current->Option.forEach(form => form.submit())
    }
  }, [formRef])

  useSubmitPaymentData(submitCallback)

  let bottomElement = <InfoElement />
  let isSpacedInnerLayout = config.appearance.innerLayout === Spaced
  let isRenderDynamicFieldsInsideBilling =
    DynamicFieldInput.groupElementsByRow(elementsInsideBilling)->Array.length > 0
  let isInfoElementPresent = React.useMemo(() => {
    PaymentMethodsRecord.getPaymentMethodsFields(~localeString)
    ->Array.find(pm => pm.paymentMethodName === paymentMethodType)
    ->Option.map(pm => pm.fields->Array.includes(PaymentMethodsRecord.InfoElement))
    ->Option.getOr(false)
  }, [paymentMethodType])
  let isRenderInfoElement =
    isInfoElementPresent && !isDisableInfoElement && redirectionInfo === ShowRedirectionInfo

  let spacedStylesForBillingDetails = isSpacedInnerLayout ? "p-2" : "my-2"
  let hasAnyField =
    DynamicFieldInput.groupElementsByRow(elementsOutsideBilling)->Array.length > 0 ||
      DynamicFieldInput.groupElementsByRow(elementsInsideBilling)->Array.length > 0
  let setAreRequiredFieldsValid = Recoil.useSetRecoilState(areRequiredFieldsValid)

  <>
    <RenderIf condition={!isSavedCardFlow && hasAnyField}>
      <ReactFinalForm.Form
        initialValues={Some(initialValues)}
        onSubmit={_values => ()}
        render={formProps => {
          formRef.current = Some(formProps.form)

          ReactFinalForm.useFormStateHandler(
            ~onFormChange=values => {
              // Flatten the nested form values so keys align correctly during merge using `mergeAndFlattenToTuples`.
              let flatValues = values->JSON.Encode.object->Utils.flattenObject(false)
              setRequiredFieldsBody(_ => flatValues)
            },
            ~onValidationChange=isValid => {
              setAreRequiredFieldsValid(_ => isValid)
            },
            ~formProps,
          )

          <>
            {DynamicFieldInput.groupElementsByRow(elementsOutsideBilling)
            ->Array.mapWithIndex((row, rowIdx) => {
              <DynamicFieldsToRenderWrapper
                key={`outside-row-${rowIdx->Int.toString}`} index={rowIdx} isInside={false}>
                <DynamicFieldInput.makeRow fields={row} />
              </DynamicFieldsToRenderWrapper>
            })
            ->React.array}
            <RenderIf condition={isRenderDynamicFieldsInsideBilling}>
              <div
                className={`billing-section ${spacedStylesForBillingDetails} w-full text-left`}
                style={
                  border: {isSpacedInnerLayout ? `1px solid ${themeObj.borderColor}` : ""},
                  borderRadius: {isSpacedInnerLayout ? themeObj.borderRadius : ""},
                }>
                <div
                  className="billing-details-text"
                  style={
                    marginBottom: "5px",
                    fontSize: themeObj.fontSizeLg,
                    opacity: "0.6",
                  }>
                  {React.string(localeString.billingDetailsText)}
                </div>
                <div
                  className="flex flex-col"
                  style={
                    gap: isSpacedInnerLayout ? themeObj.spacingGridRow : "",
                  }>
                  {DynamicFieldInput.groupElementsByRow(elementsInsideBilling)
                  ->Array.mapWithIndex((row, rowIdx) => {
                    <DynamicFieldsToRenderWrapper
                      key={`inside-row-${rowIdx->Int.toString}`} index={rowIdx}>
                      <DynamicFieldInput.makeRow fields={row} />
                    </DynamicFieldsToRenderWrapper>
                  })
                  ->React.array}
                </div>
              </div>
            </RenderIf>
            <Surcharge paymentMethod paymentMethodType />
          </>
        }}
      />
    </RenderIf>
    <RenderIf condition={isRenderInfoElement}>
      {if hasAnyField {
        bottomElement
      } else {
        <Block bottomElement />
      }}
    </RenderIf>
  </>
}
