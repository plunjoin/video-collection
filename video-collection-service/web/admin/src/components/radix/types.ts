export interface ValidationRule {
  required?: boolean
  message?: string
  trigger?: string | string[]
  min?: number
  max?: number
  type?: string
  validator?: (rule: ValidationRule, value: unknown) => boolean | string | Promise<boolean | string>
}

export type FormRules = Record<string, ValidationRule | ValidationRule[]>

export interface FormInstance {
  validate(callback?: (valid: boolean, fields?: Record<string, string>) => unknown): Promise<boolean>
  resetFields(): void
}

export interface UploadFile {
  raw: File
  name: string
  size: number
}
