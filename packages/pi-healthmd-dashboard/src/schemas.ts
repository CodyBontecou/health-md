import { Ajv2020, type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import providerSectionsSchema from "../schemas/provider-sections-v1.schema.json" with { type: "json" };
import unifiedV9Schema from "../schemas/unified-health-data-v9.schema.json" with { type: "json" };
import type { JsonValue } from "./model.js";

function validDateParts(year: number, month: number, day: number): boolean {
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1]!;
}

const ajv = new Ajv2020({ allErrors: true, strict: false, validateFormats: true });
ajv.addFormat("date", {
  type: "string",
  validate(value: string) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    return Boolean(match && validDateParts(Number(match[1]), Number(match[2]), Number(match[3])));
  },
});
ajv.addFormat("date-time", {
  type: "string",
  validate(value: string) {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/.exec(value);
    return Boolean(match && validDateParts(Number(match[1]), Number(match[2]), Number(match[3])) && Number(match[4]) <= 23 && Number(match[5]) <= 59 && Number(match[6]) <= 59);
  },
});

const validateUnifiedV9 = ajv.compile(unifiedV9Schema) as ValidateFunction<JsonValue>;
const validateProviderSections = ajv.compile(providerSectionsSchema) as ValidateFunction<JsonValue>;

function describe(error: ErrorObject): string {
  const path = error.instancePath || "$";
  if (error.keyword === "required") return `${path}: missing required property ${String(error.params.missingProperty)}`;
  if (error.keyword === "additionalProperties") return `${path}: unknown property ${String(error.params.additionalProperty)}`;
  return `${path}: ${error.message ?? error.keyword}`;
}

function errors(validate: ValidateFunction<JsonValue>, value: JsonValue): string[] {
  return validate(value) ? [] : (validate.errors ?? []).slice(0, 100).map(describe);
}

export function validateUnifiedV9Schema(value: JsonValue): string[] {
  return errors(validateUnifiedV9, value);
}

export function validateProviderSectionsSchema(value: JsonValue): string[] {
  return errors(validateProviderSections, value);
}
