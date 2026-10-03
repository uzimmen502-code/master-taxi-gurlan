'use strict';

/**
 * 13.2.1 — SXEMA YUKLOVCHI VA VALIDATOR.
 *
 * Ajv bir marta kompilyatsiya qilinadi va modul darajasida saqlanadi:
 * sovuq startda bir marta, keyingi chaqiruvlarda bepul.
 *
 * Xato xabarlari FOYDALANUVCHIGA emas, logga va dasturchiga. Klientga
 * `invalid-argument` + qisqa maydon nomi ketadi — sxema tafsiloti tashqariga
 * chiqmaydi (nimani tekshirayotganimizni raqobatchiga ko'rsatmaslik uchun
 * emas, shunchaki foydasiz bo'lgani uchun).
 */

const Ajv = require('ajv');
const addFormats = require('ajv-formats');

const demandInputSchema = require('./schemas/demand_input.schema.json');
const offerInputSchema = require('./schemas/offer_input.schema.json');
const serviceAttrSchema = require('./schemas/attributes/service.schema.json');

/**
 * Modul -> attribut sxemasi.
 *
 * Modul bu ro'yxatda bo'lmasa, `attributes` BO'SH bo'lishi SHART.
 * Shunda yangi modul tasodifan tekshirilmagan ma'lumot yozib yubormaydi.
 */
const ATTRIBUTE_SCHEMAS = {
  service: serviceAttrSchema,
};

const ajv = new Ajv({
  allErrors: true,
  removeAdditional: false,
  useDefaults: true,
  coerceTypes: false,
  strict: false,
});
addFormats(ajv);

const validators = {
  demandInput: ajv.compile(demandInputSchema),
  offerInput: ajv.compile(offerInputSchema),
};

const attributeValidators = {};
for (const [mod, schema] of Object.entries(ATTRIBUTE_SCHEMAS)) {
  attributeValidators[mod] = ajv.compile(schema);
}

/** Ajv xatolarini qisqa, o'qiladigan satrlarga aylantiradi. */
function formatErrors(errors) {
  if (!errors || !errors.length) return [];
  return errors.map((e) => {
    const where = e.instancePath || '(ildiz)';
    if (e.keyword === 'additionalProperties') {
      return `${where}: ruxsatsiz maydon «${e.params.additionalProperty}»`;
    }
    if (e.keyword === 'required') {
      return `${where}: «${e.params.missingProperty}» majburiy`;
    }
    if (e.keyword === 'enum') {
      return `${where}: ruxsat etilgan qiymatlar — ${(e.params.allowedValues || []).join(', ')}`;
    }
    return `${where}: ${e.message}`;
  });
}

/**
 * Natija: `{ valid, errors, value }`.
 *
 * DIQQAT: `useDefaults: true` sabab `value` yuklamadan FARQ QILADI —
 * standart qiymatlar qo'shilgan bo'ladi. Shuning uchun chaqiruvchi
 * `result.value`ni ishlatishi kerak, asl `data`ni emas.
 */
function runValidator(validate, data) {
  // Ajv `useDefaults` bilan obyektni JOYIDA o'zgartiradi — nusxa olamiz,
  // chaqiruvchining yuklamasi kutilmaganda o'zgarib qolmasin.
  const value = data === undefined || data === null
    ? {}
    : JSON.parse(JSON.stringify(data));
  const valid = validate(value);
  return { valid, errors: valid ? [] : formatErrors(validate.errors), value };
}

/** `createDemand` yuklamasi. */
function validateDemandInput(data) {
  return runValidator(validators.demandInput, data);
}

/** `submitOffer` yuklamasi. */
function validateOfferInput(data) {
  return runValidator(validators.offerInput, data);
}

/**
 * Modulga xos `attributes`.
 *
 * Sxemasi yo'q modul uchun `attributes` bo'sh bo'lishi SHART — aks holda
 * tekshirilmagan ma'lumot bazaga tushardi.
 */
function validateAttributes(module, attributes) {
  const validate = attributeValidators[module];
  if (!validate) {
    const keys = Object.keys(attributes || {});
    if (keys.length === 0) return { valid: true, errors: [], value: {} };
    return {
      valid: false,
      errors: [`«${module}» moduli uchun attribut sxemasi yo'q, `
        + `lekin attributes bo'sh emas: ${keys.join(', ')}`],
      value: {},
    };
  }
  return runValidator(validate, attributes || {});
}

/**
 * To'liq tekshiruv: yuklama + attributlar birga.
 *
 * Nega birga: `attributes` sxemasi MODULGA bog'liq, shuning uchun modulni
 * bilmasdan uni tekshirib bo'lmaydi. Ikki qadamni bitta joyda ushlab
 * turish chaqiruvchida «attributni tekshirishni esdan chiqarish» xatosini
 * imkonsiz qiladi.
 */
function validateCreateDemand(data) {
  const base = validateDemandInput(data);
  if (!base.valid) return base;

  const attrs = validateAttributes(base.value.module, base.value.attributes);
  if (!attrs.valid) {
    return {
      valid: false,
      errors: attrs.errors.map((e) => `attributes${e}`),
      value: base.value,
    };
  }

  base.value.attributes = attrs.value;
  return base;
}

/** Sxemasi mavjud modullar ro'yxati (test va admin panel uchun). */
function modulesWithAttributeSchema() {
  return Object.keys(ATTRIBUTE_SCHEMAS);
}

module.exports = {
  validateDemandInput,
  validateOfferInput,
  validateAttributes,
  validateCreateDemand,
  modulesWithAttributeSchema,
  formatErrors,
  ATTRIBUTE_SCHEMAS,
};
