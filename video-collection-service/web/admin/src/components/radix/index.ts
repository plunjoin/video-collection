import {
  computed,
  defineComponent,
  Fragment,
  h,
  inject,
  isVNode,
  nextTick,
  provide,
  reactive,
  ref,
  renderSlot,
  watch,
  type App,
  type Component,
  type Directive,
  type Plugin,
  type PropType,
  type VNode,
  type VNodeChild,
} from 'vue'
import {
  CheckboxGroupRoot as RCheckboxGroupRoot,
  CheckboxIndicator as RCheckboxIndicator,
  CheckboxRoot as RCheckboxRoot,
  DialogClose as RDialogClose,
  DialogContent as RDialogContent,
  DialogOverlay as RDialogOverlay,
  DialogPortal as RDialogPortal,
  DialogRoot as RDialogRoot,
  DialogTitle as RDialogTitle,
  DropdownMenuContent as RDropdownMenuContent,
  DropdownMenuItem as RDropdownMenuItem,
  DropdownMenuPortal as RDropdownMenuPortal,
  DropdownMenuRoot as RDropdownMenuRoot,
  DropdownMenuTrigger as RDropdownMenuTrigger,
  RadioGroupIndicator as RRadioGroupIndicator,
  RadioGroupItem as RRadioGroupItem,
  RadioGroupRoot as RRadioGroupRoot,
  ScrollAreaCorner as RScrollAreaCorner,
  ScrollAreaRoot as RScrollAreaRoot,
  ScrollAreaScrollbar as RScrollAreaScrollbar,
  ScrollAreaThumb as RScrollAreaThumb,
  ScrollAreaViewport as RScrollAreaViewport,
  SelectContent as RSelectContent,
  SelectItem as RSelectItem,
  SelectItemText as RSelectItemText,
  SelectPortal as RSelectPortal,
  SelectRoot as RSelectRoot,
  SelectTrigger as RSelectTrigger,
  SelectValue as RSelectValue,
  SelectViewport as RSelectViewport,
  SwitchRoot as RSwitchRoot,
  SwitchThumb as RSwitchThumb,
  TabsContent as RTabsContent,
  TabsList as RTabsList,
  TabsRoot as RTabsRoot,
  TabsTrigger as RTabsTrigger,
  TooltipContent as RTooltipContent,
  TooltipPortal as RTooltipPortal,
  TooltipProvider as RTooltipProvider,
  TooltipRoot as RTooltipRoot,
  TooltipTrigger as RTooltipTrigger,
  ToggleGroupItem as RToggleGroupItem,
  ToggleGroupRoot as RToggleGroupRoot,
} from 'reka-ui'

const emptySlot = () => []

function collectVNodes(value: unknown, output: VNode[] = []): VNode[] {
  if (Array.isArray(value)) {
    for (const child of value) collectVNodes(child, output)
    return output
  }
  if (!isVNode(value)) return output
  if (value.type === Fragment && Array.isArray(value.children)) {
    collectVNodes(value.children, output)
  } else if (typeof value.type !== 'symbol') {
    output.push(value)
  }
  return output
}

function primitive(component: unknown, props?: Record<string, unknown> | null, children?: unknown): VNode {
  return h(component as Component, props as never, children as never)
}

function vnodeSlot(node: VNode, name = 'default'): VNodeChild[] {
  const children = node.children
  if (Array.isArray(children)) return children as VNodeChild[]
  if (!children || typeof children !== 'object') {
    return typeof children === 'string' ? [children] : []
  }
  const slot = (children as Record<string, unknown>)[name]
  if (typeof slot === 'function') return (slot as () => VNodeChild[])() ?? []
  return Array.isArray(slot) ? slot as VNodeChild[] : typeof slot === 'string' ? [slot] : []
}

function vnodeText(node: VNode): string {
  if (typeof node.children === 'string') return node.children
  const value = vnodeSlot(node).map((child) => {
    if (typeof child === 'string' || typeof child === 'number') return String(child)
    return isVNode(child) ? vnodeText(child) : ''
  }).join('')
  return value
}

function vnodeProp(node: VNode, key: string, alias?: string): unknown {
  return node.props?.[key] ?? (alias ? node.props?.[alias] : undefined)
}

function toCssUnit(val: unknown): string | undefined {
  if (val === undefined || val === null || val === '') return undefined
  if (typeof val === 'number') return `${val}px`
  if (typeof val === 'string') {
    const trimmed = val.trim()
    if (/^\d+(\.\d+)?$/.test(trimmed)) return `${trimmed}px`
    return trimmed
  }
  return undefined
}

function simpleSlot(tag: string, className: string, extraProps?: Record<string, unknown>): Component {
  return defineComponent({
    inheritAttrs: false,
    setup(_, { attrs, slots }) {
      return () => h(tag, { ...extraProps, ...attrs, class: [className, attrs.class] }, renderSlot(slots, 'default'))
    },
  })
}

const ConfigProvider = defineComponent({
  name: 'RConfigProvider',
  setup(_, { slots }) {
    return () => renderSlot(slots, 'default')
  },
})

const Alert = defineComponent({
  name: 'RAlert',
  inheritAttrs: false,
  props: {
    title: String,
    type: { type: String, default: 'info' },
    closable: Boolean,
    showIcon: Boolean,
  },
  emits: ['close'],
  setup(props, { attrs, emit, slots }) {
    const visible = ref(true)
    return () => visible.value ? h('section', {
      ...attrs,
      class: ['r-alert', `r-alert--${props.type}`, attrs.class],
      role: 'status',
    }, [
      props.showIcon ? h('span', { class: 'r-alert__icon', 'aria-hidden': 'true' }, props.type === 'error' ? '×' : props.type === 'warning' ? '!' : 'i') : null,
      h('div', { class: 'r-alert__body' }, [
        props.title ? h('strong', { class: 'r-alert__title' }, props.title) : null,
        h('div', { class: 'r-alert__description' }, renderSlot(slots, 'default')),
      ]),
      props.closable ? h('button', {
        class: 'r-alert__close',
        type: 'button',
        'aria-label': 'Close',
        onClick: () => { visible.value = false; emit('close') },
      }, '×') : null,
    ]) : null
  },
})

const Avatar = defineComponent({
  name: 'RAvatar',
  props: { src: String, alt: String, size: { type: [String, Number], default: 'medium' } },
  setup(props, { attrs, slots }) {
    const size = computed(() => typeof props.size === 'number' ? `${props.size}px` : undefined)
    return () => h('span', { ...attrs, class: ['r-avatar', `r-avatar--${props.size}`, attrs.class], style: [{ width: size.value, height: size.value }, attrs.style] }, [
      props.src ? h('img', { src: props.src, alt: props.alt ?? '' }) : renderSlot(slots, 'default'),
    ])
  },
})

const Badge = defineComponent({
  name: 'RBadge',
  props: { value: [String, Number], hidden: Boolean, type: { type: String, default: 'primary' } },
  setup(props, { attrs, slots }) {
    return () => h('span', { ...attrs, class: ['r-badge-wrap', attrs.class] }, [
      renderSlot(slots, 'default'),
      !props.hidden && props.value !== undefined && props.value !== ''
        ? h('span', { class: ['r-badge', `r-badge--${props.type}`] }, String(props.value))
        : null,
    ])
  },
})

const Button = defineComponent({
  name: 'RButton',
  inheritAttrs: false,
  props: {
    type: { type: String, default: 'default' },
    nativeType: { type: String, default: 'button' },
    disabled: Boolean,
    loading: Boolean,
    size: String,
    icon: { type: [Object, Function, String] as PropType<Component | string>, default: undefined },
    plain: Boolean,
    link: Boolean,
    text: Boolean,
    circle: Boolean,
    round: Boolean,
  },
  emits: ['click'],
  setup(props, { attrs, emit, slots }) {
    return () => h('button', {
      ...attrs,
      type: props.nativeType,
      disabled: props.disabled || props.loading,
      'aria-busy': props.loading || undefined,
      class: ['r-button', `r-button--${props.type}`, props.size ? `r-button--${props.size}` : '', props.plain ? 'r-button--plain' : '', props.link ? 'r-button--link' : '', props.text ? 'r-button--text' : '', props.circle ? 'r-button--circle' : '', props.round ? 'r-button--round' : '', attrs.class],
      onClick: (event: MouseEvent) => emit('click', event),
    }, [
      props.loading ? h('span', { class: 'r-spinner', 'aria-hidden': 'true' }) : props.icon ? typeof props.icon === 'string' ? h('span', { class: `r-button__status-icon r-button__status-icon--${props.icon}`, 'aria-hidden': 'true' }, props.icon === 'success' ? '✓' : props.icon === 'error' ? '×' : props.icon) : h(props.icon as Component, { size: props.size === 'small' ? 12 : props.size === 'large' ? 16 : 13, class: 'r-button__icon', 'aria-hidden': 'true' }) : null,
      renderSlot(slots, 'default'),
    ])
  },
})

const ButtonGroup = simpleSlot('div', 'r-button-group')
const Card = defineComponent({
  name: 'RCard',
  inheritAttrs: false,
  props: { header: String, shadow: { type: String, default: 'never' }, bodyStyle: { type: [Object, String] as PropType<Record<string, string> | string>, default: undefined } },
  setup(props, { attrs, slots }) {
    return () => h('section', { ...attrs, class: ['r-card', `r-card--${props.shadow}`, attrs.class] }, [
      slots.header || props.header ? h('header', { class: 'r-card__header' }, slots.header ? renderSlot(slots, 'header') : props.header) : null,
      h('div', { class: 'r-card__body', style: props.bodyStyle }, renderSlot(slots, 'default')),
      slots.footer ? h('footer', { class: 'r-card__footer' }, renderSlot(slots, 'footer')) : null,
    ])
  },
})

const Checkbox = defineComponent({
  name: 'RCheckbox',
  inheritAttrs: false,
  props: { modelValue: { type: Boolean as PropType<boolean | undefined>, default: undefined }, value: [String, Number], disabled: Boolean, label: String },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    return () => primitive(RCheckboxRoot, {
      ...attrs,
      ...(props.modelValue !== undefined ? { modelValue: props.modelValue } : {}),
      value: props.value,
      disabled: props.disabled,
      class: ['r-checkbox', attrs.class],
      'aria-label': props.label,
      'onUpdate:modelValue': (value: boolean | 'indeterminate') => {
        emit('update:modelValue', value)
        emit('change', value)
      },
    }, {
      default: () => [primitive(RCheckboxIndicator, { class: 'r-checkbox__indicator' }, () => '✓'),
        h('span', { class: 'r-checkbox__label' }, slots.default ? renderSlot(slots, 'default') : props.label)],
    })
  },
})

const CheckboxGroup = defineComponent({
  name: 'RCheckboxGroup',
  inheritAttrs: false,
  props: { modelValue: { type: Array as PropType<Array<string | number>>, default: () => [] }, disabled: Boolean },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    return () => primitive(RCheckboxGroupRoot, {
      ...attrs,
      modelValue: props.modelValue,
      disabled: props.disabled,
      class: ['r-checkbox-group', attrs.class],
      'onUpdate:modelValue': (value: Array<string | number>) => {
        emit('update:modelValue', value)
        emit('change', value)
      },
    }, { default: () => renderSlot(slots, 'default') })
  },
})

const Col = defineComponent({
  name: 'RCol',
  inheritAttrs: false,
  props: {
    span: { type: [Number, String], default: 0 },
    offset: { type: [Number, String], default: 0 },
    xs: [Number, String], sm: [Number, String], md: [Number, String], lg: [Number, String], xl: [Number, String],
  },
  setup(props, { attrs, slots }) {
    return () => h('div', {
      ...attrs,
      class: ['r-col', `r-col--xs-${props.xs ?? props.span ?? 24}`, props.sm !== undefined ? `r-col--sm-${props.sm}` : '', props.md !== undefined ? `r-col--md-${props.md}` : '', props.lg !== undefined ? `r-col--lg-${props.lg}` : '', props.xl !== undefined ? `r-col--xl-${props.xl}` : '', attrs.class],
      style: [{ marginInlineStart: props.offset ? `${Number(props.offset) / 24 * 100}%` : undefined }, attrs.style],
    }, renderSlot(slots, 'default'))
  },
})

const CollapseItem = defineComponent({
  name: 'RCollapseItem',
  props: { title: String, name: [String, Number], disabled: Boolean },
  setup(props, { attrs, slots }) {
    return () => h('details', { ...attrs, class: ['r-collapse-item', attrs.class], disabled: props.disabled || undefined }, [
      h('summary', { class: 'r-collapse-item__title' }, [props.title, renderSlot(slots, 'title')]),
      h('div', { class: 'r-collapse-item__content' }, renderSlot(slots, 'default')),
    ])
  },
})
const Collapse = simpleSlot('div', 'r-collapse')

function createNativeInput(name: string, defaultType: string, valueType: 'string' | 'number' = 'string'): Component {
  return defineComponent({
    name,
    inheritAttrs: false,
    props: {
      modelValue: { type: [String, Number] as PropType<string | number>, default: '' },
      placeholder: String,
      disabled: Boolean,
      type: { type: String, default: defaultType },
      rows: { type: Number, default: 3 },
      clearable: Boolean,
      showWordLimit: Boolean,
    },
    emits: ['update:modelValue', 'input', 'change', 'focus', 'blur', 'clear'],
    setup(props, { attrs, emit, slots }) {
      const update = (event: Event, eventName: 'input' | 'change') => {
        const value = (event.target as HTMLInputElement | HTMLTextAreaElement).value
        const result = valueType === 'number' && value !== '' ? Number(value) : value
        emit('update:modelValue', result)
        emit(eventName, result, event)
      }
      const clear = () => { emit('update:modelValue', valueType === 'number' ? 0 : ''); emit('clear') }
      return () => {
        const control = props.type === 'textarea'
          ? h('textarea', {
              ...attrs,
              class: ['r-input', 'r-input--textarea', attrs.class],
              rows: props.rows,
              value: props.modelValue,
              placeholder: props.placeholder,
              disabled: props.disabled,
              onInput: (event: Event) => update(event, 'input'),
              onChange: (event: Event) => update(event, 'change'),
              onFocus: (event: FocusEvent) => emit('focus', event),
              onBlur: (event: FocusEvent) => emit('blur', event),
            })
          : h('input', {
              ...attrs,
              class: ['r-input', attrs.class],
              type: props.type,
              value: props.modelValue,
              placeholder: props.placeholder,
              disabled: props.disabled,
              onInput: (event: Event) => update(event, 'input'),
              onChange: (event: Event) => update(event, 'change'),
              onFocus: (event: FocusEvent) => emit('focus', event),
              onBlur: (event: FocusEvent) => emit('blur', event),
            })
        if (!slots.prefix && !slots.suffix && !props.clearable && !props.showWordLimit) return control
        const valueLength = String(props.modelValue ?? '').length
        return h('span', { class: ['r-input-wrap', props.type === 'textarea' ? 'r-input-wrap--textarea' : ''] }, [
          slots.prefix ? h('span', { class: 'r-input__prefix' }, renderSlot(slots, 'prefix')) : null,
          control,
          slots.suffix ? h('span', { class: 'r-input__suffix' }, renderSlot(slots, 'suffix')) : null,
          props.clearable && !props.disabled && props.modelValue !== '' ? h('button', { type: 'button', class: 'r-input__clear', 'aria-label': 'Clear', onClick: clear }, '×') : null,
          props.showWordLimit && attrs.maxlength ? h('span', { class: 'r-input__limit' }, `${valueLength}/${attrs.maxlength}`) : null,
        ])
      }
    },
  })
}
const DatePicker = createNativeInput('RDatePicker', 'date')

const DescriptionsItem = defineComponent({
  name: 'RDescriptionsItem',
  props: { label: String },
  setup(props, { attrs, slots }) {
    return () => h('div', { ...attrs, class: ['r-descriptions-item', attrs.class] }, [
      h('dt', { class: 'r-descriptions-item__label' }, props.label),
      h('dd', { class: 'r-descriptions-item__content' }, renderSlot(slots, 'default')),
    ])
  },
})
const Descriptions = defineComponent({
  name: 'RDescriptions',
  inheritAttrs: false,
  props: { title: String, column: { type: Number, default: 3 }, border: Boolean },
  setup(props, { attrs, slots }) {
    return () => h('section', { ...attrs, class: ['r-descriptions', props.border ? 'r-descriptions--border' : '', attrs.class] }, [
      props.title ? h('h3', { class: 'r-descriptions__title' }, props.title) : null,
      h('dl', { class: 'r-descriptions__grid', style: { '--r-description-columns': props.column } }, renderSlot(slots, 'default')),
    ])
  },
})

function createDialogComponent(name: string, drawer = false): Component {
  return defineComponent({
    name,
    inheritAttrs: false,
    props: {
      modelValue: Boolean,
      title: String,
      width: { type: [String, Number] as PropType<string | number>, default: drawer ? '28rem' : '32rem' },
      direction: { type: String, default: 'rtl' },
      top: String,
    },
    emits: ['update:modelValue', 'open', 'close'],
    setup(props, { attrs, emit, slots }) {
      return () => primitive(RDialogRoot, {
        open: props.modelValue,
        modal: true,
        'onUpdate:open': (open: boolean) => {
          emit('update:modelValue', open)
          emit(open ? 'open' : 'close')
        },
      }, {
        default: () => primitive(RDialogPortal, null, {
          default: () => [
            primitive(RDialogOverlay, { class: 'r-overlay' }),
            primitive(RDialogContent, {
              ...attrs,
              class: [drawer ? 'r-drawer' : 'r-dialog', drawer ? `r-drawer--${props.direction}` : '', attrs.class],
              style: [{ width: typeof props.width === 'number' ? `${props.width}px` : props.width, ...(props.top ? { insetBlockStart: props.top, transform: 'translateX(-50%)' } : {}) }, attrs.style],
              'data-state': props.modelValue ? 'open' : 'closed',
            }, {
              default: () => [
                h('header', { class: `${drawer ? 'r-drawer' : 'r-dialog'}__header` }, [
                  primitive(RDialogTitle, { class: 'r-dialog__title' }, () => props.title ?? ''),
                  primitive(RDialogClose, { class: 'r-dialog__close', 'aria-label': 'Close' }, () => '×'),
                ]),
                h('div', { class: `${drawer ? 'r-drawer' : 'r-dialog'}__body` }, renderSlot(slots, 'default')),
                slots.footer ? h('footer', { class: `${drawer ? 'r-drawer' : 'r-dialog'}__footer` }, renderSlot(slots, 'footer')) : null,
              ],
            }),
          ],
        }),
      })
    },
  })
}
const Dialog = createDialogComponent('RDialog')
const Drawer = createDialogComponent('RDrawer', true)

const Divider = defineComponent({
  name: 'RDivider',
  props: { direction: { type: String, default: 'horizontal' }, contentPosition: String },
  setup(props, { attrs, slots }) {
    return () => h('div', { ...attrs, class: ['r-divider', `r-divider--${props.direction}`, attrs.class], role: 'separator' },
      slots.default ? [h('span', { class: 'r-divider__label' }, renderSlot(slots, 'default'))] : [])
  },
})

const DropdownItem = defineComponent({ name: 'RDropdownItem', setup: () => () => null })
const DropdownMenu = defineComponent({ name: 'RDropdownMenu', setup: () => () => null })
function dropdownItems(nodes: unknown): VNode[] {
  return collectVNodes(nodes).flatMap((node) => {
    if (node.type === DropdownMenu) return dropdownItems(vnodeSlot(node))
    return node.type === DropdownItem ? [node] : []
  })
}
const Dropdown = defineComponent({
  name: 'RDropdown',
  inheritAttrs: false,
  emits: ['command'],
  setup(_, { attrs, emit, slots }) {
    return () => {
      const items = dropdownItems(slots.dropdown?.() ?? emptySlot())
      return primitive(RDropdownMenuRoot, null, {
        default: () => [
          primitive(RDropdownMenuTrigger, { ...attrs, asChild: true, class: ['r-dropdown__trigger', attrs.class] }, {
            default: () => renderSlot(slots, 'default'),
          }),
          primitive(RDropdownMenuPortal, null, {
            default: () => primitive(RDropdownMenuContent, { class: 'r-dropdown__content', sideOffset: 6 }, () => items.map((node, index) => {
              const command = vnodeProp(node, 'command')
              const disabled = Boolean(vnodeProp(node, 'disabled'))
              const label = vnodeProp(node, 'label')
              return primitive(RDropdownMenuItem, {
                key: index,
                disabled,
                class: 'r-dropdown__item',
                onSelect: () => emit('command', command),
              }, () => label ?? vnodeSlot(node))
            })),
          }),
        ],
      })
    }
  },
})

const Empty = defineComponent({
  name: 'REmpty',
  props: { description: { type: String, default: 'No data' }, image: String },
  setup(props, { attrs, slots }) {
    return () => h('div', { ...attrs, class: ['r-empty', attrs.class] }, [
      props.image ? h('img', { src: props.image, alt: '', class: 'r-empty__image' }) : h('div', { class: 'r-empty__illustration', 'aria-hidden': 'true' }, '—'),
      h('p', { class: 'r-empty__description' }, renderSlot(slots, 'default', {}, () => [props.description])),
      slots.footer ? h('div', { class: 'r-empty__footer' }, renderSlot(slots, 'footer')) : null,
    ])
  },
})

const formErrorsKey = Symbol('r-form-errors')
const formContextKey = Symbol('r-form-context')
interface FormContext { labelWidth?: string | number; labelPosition?: string; inline?: boolean; disabled?: boolean }
interface FormRule { required?: boolean; message?: string; min?: number; max?: number; type?: string; validator?: (rule: FormRule, value: unknown) => boolean | string | Promise<boolean | string> }
const Form = defineComponent({
  name: 'RForm',
  inheritAttrs: false,
  props: {
    model: { type: Object as PropType<Record<string, unknown>>, default: () => ({}) },
    rules: { type: Object as PropType<Record<string, FormRule | FormRule[]>>, default: () => ({}) },
    labelPosition: String,
    labelWidth: { type: [String, Number] as PropType<string | number>, default: undefined },
    inline: Boolean,
    disabled: Boolean,
  },
  emits: ['submit', 'reset', 'validate'],
  setup(props, { attrs, emit, slots, expose }) {
    const errors = reactive<Record<string, string>>({})
    const initial = JSON.parse(JSON.stringify(props.model ?? {})) as Record<string, unknown>
    provide(formErrorsKey, errors)
    provide(formContextKey, {
      get labelWidth() { return props.labelWidth },
      get labelPosition() { return props.labelPosition },
      get inline() { return props.inline },
      get disabled() { return props.disabled },
    } satisfies FormContext)
    const validate = async (callback?: (valid: boolean, fields?: Record<string, string>) => unknown) => {
      for (const key of Object.keys(errors)) delete errors[key]
      for (const [field, ruleSet] of Object.entries(props.rules)) {
        const value = props.model?.[field]
        for (const rule of Array.isArray(ruleSet) ? ruleSet : [ruleSet]) {
          let message = ''
          if (rule.required && (value === undefined || value === null || String(value).trim() === '')) message = rule.message || `${field} is required`
          if (!message && typeof value === 'string' && rule.min !== undefined && value.length < rule.min) message = rule.message || `${field} is too short`
          if (!message && typeof value === 'string' && rule.max !== undefined && value.length > rule.max) message = rule.message || `${field} is too long`
          if (!message && rule.type === 'email' && value && !/^\S+@\S+\.\S+$/.test(String(value))) message = rule.message || `${field} is not a valid email`
          if (!message && rule.validator) {
            const result = await rule.validator(rule, value)
            if (result !== true) message = typeof result === 'string' ? result : rule.message || `${field} is invalid`
          }
          if (message) { errors[field] = message; break }
        }
      }
      await nextTick()
      const valid = Object.keys(errors).length === 0
      emit('validate', valid, errors)
      if (callback) await callback(valid, errors)
      return valid
    }
    const resetFields = () => {
      Object.assign(props.model, JSON.parse(JSON.stringify(initial)))
      for (const key of Object.keys(errors)) delete errors[key]
    }
    expose({ validate, resetFields })
    return () => h('form', {
      ...attrs,
      class: ['r-form', props.inline ? 'r-form--inline' : '', props.labelPosition === 'top' ? 'r-form--labels-top' : '', attrs.class],
      style: [{ '--r-label-width': typeof props.labelWidth === 'number' ? `${props.labelWidth}px` : props.labelWidth }, attrs.style],
      onSubmit: (event: SubmitEvent) => { event.preventDefault(); emit('submit', event) },
      onReset: (event: Event) => emit('reset', event),
    }, props.disabled
      ? h('fieldset', { class: 'r-form__fieldset', disabled: true }, renderSlot(slots, 'default'))
      : renderSlot(slots, 'default'))
  },
})
const FormItem = defineComponent({
  name: 'RFormItem',
  props: { label: String, prop: String, required: Boolean },
  setup(props, { attrs, slots }) {
    const errors = inject<Record<string, string>>(formErrorsKey, {})
    const form = inject<FormContext>(formContextKey, {})
    return () => h('div', { ...attrs, class: ['r-form-item', form.inline ? 'r-form-item--inline' : '', form.labelPosition === 'top' ? 'r-form-item--top' : '', attrs.class], 'data-invalid': props.prop && errors[props.prop] ? '' : undefined }, [
      props.label ? h('label', { class: 'r-form-item__label', style: { width: form.labelPosition === 'top' ? undefined : typeof form.labelWidth === 'number' ? `${form.labelWidth}px` : form.labelWidth } }, [props.label, props.required ? h('span', { class: 'r-required', 'aria-hidden': 'true' }, ' *') : null]) : null,
      h('div', { class: 'r-form-item__content' }, renderSlot(slots, 'default')),
      props.prop && errors[props.prop] ? h('div', { class: 'r-form-item__error', role: 'alert' }, errors[props.prop]) : slots.error ? h('div', { class: 'r-form-item__error' }, renderSlot(slots, 'error')) : null,
    ])
  },
})
const Icon = defineComponent({ name: 'RIcon', props: { name: String }, setup(props, { attrs, slots }) { return () => h('span', { ...attrs, class: ['r-icon', attrs.class], 'aria-hidden': 'true' }, renderSlot(slots, 'default', {}, () => [props.name ?? ''])) } })
const Image = defineComponent({
  name: 'RImage',
  inheritAttrs: false,
  props: {
    src: String,
    alt: String,
    fit: { type: String, default: 'cover' },
    width: [String, Number],
    height: [String, Number],
    previewSrcList: { type: Array as PropType<string[]>, default: () => [] },
    previewTeleported: Boolean,
  },
  setup(props, { attrs, slots }) {
    const failed = ref(false)
    const previewOpen = ref(false)
    const previewIndex = ref(0)
    const images = computed(() => props.previewSrcList.length ? props.previewSrcList : props.src ? [props.src] : [])
    const size = (value?: string | number) => typeof value === 'number' ? `${value}px` : value
    const move = (delta: number) => { previewIndex.value = (previewIndex.value + delta + images.value.length) % images.value.length }
    return () => h(Fragment, null, [
      failed.value
        ? slots.error ? renderSlot(slots, 'error') : h('div', { class: ['r-image r-image--error', attrs.class] }, '图片加载失败')
        : h('img', {
            ...attrs,
            class: ['r-image', images.value.length ? 'r-image--previewable' : '', attrs.class],
            src: props.src,
            alt: props.alt ?? '',
            style: [{ objectFit: props.fit, width: size(props.width), height: size(props.height) }, attrs.style],
            onError: () => { failed.value = true },
            onClick: images.value.length ? () => { previewIndex.value = Math.max(0, images.value.indexOf(props.src || '')); previewOpen.value = true } : undefined,
          }),
      previewOpen.value ? primitive(RDialogRoot, { open: previewOpen.value, 'onUpdate:open': (open: boolean) => { previewOpen.value = open } }, {
        default: () => primitive(RDialogPortal, null, {
          default: () => [
            primitive(RDialogOverlay, { class: 'r-image-preview__overlay' }),
            primitive(RDialogContent, { class: 'r-image-preview', 'aria-describedby': undefined }, {
              default: () => [
                primitive(RDialogTitle, { class: 'r-sr-only' }, () => props.alt || '图片预览'),
                primitive(RDialogClose, { class: 'r-image-preview__close', 'aria-label': '关闭预览' }, () => '×'),
                images.value.length > 1 ? h('button', { type: 'button', class: 'r-image-preview__previous', 'aria-label': '上一张', onClick: () => move(-1) }, '‹') : null,
                h('img', { src: images.value[previewIndex.value], alt: props.alt || '图片预览', class: 'r-image-preview__image' }),
                images.value.length > 1 ? h('button', { type: 'button', class: 'r-image-preview__next', 'aria-label': '下一张', onClick: () => move(1) }, '›') : null,
                images.value.length > 1 ? h('span', { class: 'r-image-preview__count' }, `${previewIndex.value + 1} / ${images.value.length}`) : null,
              ],
            }),
          ],
        }),
      }) : null,
    ])
  },
})
const Input = createNativeInput('RInput', 'text')
const InputNumber = createNativeInput('RInputNumber', 'number', 'number')

const Link = defineComponent({
  name: 'RLink',
  props: { href: String, type: String, underline: { type: Boolean, default: true }, disabled: Boolean, target: String },
  setup(props, { attrs, slots }) {
    return () => h(props.disabled ? 'span' : 'a', {
      ...attrs,
      class: ['r-link', props.type ? `r-link--${props.type}` : '', !props.underline ? 'r-link--plain' : '', attrs.class],
      href: props.disabled ? undefined : props.href,
      target: props.target,
      'aria-disabled': props.disabled || undefined,
    }, renderSlot(slots, 'default'))
  },
})
const Option = defineComponent({
  name: 'ROption',
  props: {
    value: { type: [String, Number, Boolean], default: '' },
    label: [String, Number],
    disabled: Boolean,
  },
  setup: () => () => null,
})

const Pagination = defineComponent({
  name: 'RPagination',
  inheritAttrs: false,
  props: {
    modelValue: Number,
    currentPage: Number,
    pageSize: { type: Number, default: 10 },
    pageSizes: { type: Array as PropType<number[]>, default: () => [10, 20, 50, 100] },
    total: { type: Number, default: 0 },
    layout: { type: String, default: 'prev, pager, next' },
    disabled: Boolean,
  },
  emits: ['update:modelValue', 'update:currentPage', 'update:pageSize', 'current-change', 'size-change'],
  setup(props, { attrs, emit }) {
    const page = computed(() => Math.max(1, props.modelValue ?? props.currentPage ?? 1))
    const pages = computed(() => Math.max(1, Math.ceil(props.total / Math.max(1, props.pageSize))))
    const jump = ref(String(page.value))
    const change = (next: number) => {
      const value = Math.min(pages.value, Math.max(1, Number.isFinite(next) ? next : 1))
      jump.value = String(value)
      emit('update:modelValue', value)
      emit('update:currentPage', value)
      emit('current-change', value)
    }
    const changeSize = (event: Event) => {
      const size = Number((event.target as HTMLSelectElement).value)
      emit('update:pageSize', size)
      emit('size-change', size)
      change(1)
    }
    const button = (label: string, next: number, aria: string) => h('button', {
      class: 'r-pagination__button', type: 'button', disabled: props.disabled || next < 1 || next > pages.value,
      onClick: () => change(next), 'aria-label': aria,
    }, label)
    return () => {
      const controls: VNodeChild[] = []
      for (const part of props.layout.split(',').map((item) => item.trim())) {
        if (part === 'total') controls.push(h('span', { class: 'r-pagination__total' }, `共 ${props.total} 条`))
        else if (part === 'sizes') controls.push(h('select', { class: 'r-pagination__size', value: props.pageSize, disabled: props.disabled, 'aria-label': '每页条数', onChange: changeSize }, props.pageSizes.map((size) => h('option', { key: size, value: size }, `${size} 条/页`))))
        else if (part === 'prev') controls.push(button('‹', page.value - 1, '上一页'))
        else if (part === 'next') controls.push(button('›', page.value + 1, '下一页'))
        else if (part === 'pager') controls.push(h('span', { class: 'r-pagination__status', 'aria-live': 'polite' }, `${page.value} / ${pages.value}`))
        else if (part === 'jumper') controls.push(h('label', { class: 'r-pagination__jumper' }, ['跳至', h('input', { value: jump.value, type: 'number', min: 1, max: pages.value, onInput: (event: Event) => { jump.value = (event.target as HTMLInputElement).value }, onKeydown: (event: KeyboardEvent) => { if (event.key === 'Enter') change(Number(jump.value)) } }), '页']))
      }
      return h('nav', { ...attrs, class: ['r-pagination', attrs.class], 'aria-label': '分页导航' }, controls)
    }
  },
})

const radioGroupContext = Symbol('r-radio-group')
const RadioGroup = defineComponent({
  name: 'RRadioGroup',
  inheritAttrs: false,
  props: { modelValue: { type: [String, Number] as PropType<string | number>, default: '' }, disabled: Boolean, name: String, orientation: String },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    provide(radioGroupContext, true)
    return () => primitive(RRadioGroupRoot, {
      ...attrs,
      modelValue: props.modelValue,
      disabled: props.disabled,
      name: props.name,
      orientation: props.orientation,
      class: ['r-radio-group', attrs.class],
      'onUpdate:modelValue': (value: string | number) => { emit('update:modelValue', value); emit('change', value) },
    }, { default: () => renderSlot(slots, 'default') })
  },
})
const Radio = defineComponent({
  name: 'RRadio',
  inheritAttrs: false,
  props: { modelValue: { type: [String, Number] as PropType<string | number>, default: '' }, value: { type: [String, Number] as PropType<string | number>, default: '' }, label: String, disabled: Boolean },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    const inGroup = inject<boolean>(radioGroupContext, false)
    const item = () => primitive(RRadioGroupItem, { ...attrs, value: props.value, disabled: props.disabled, class: ['r-radio', attrs.class] }, {
      default: () => [primitive(RRadioGroupIndicator, { class: 'r-radio__indicator' }, () => '●'), h('span', { class: 'r-radio__label' }, slots.default ? renderSlot(slots, 'default') : props.label)],
    })
    return () => inGroup ? item() : primitive(RRadioGroupRoot, {
      modelValue: props.modelValue,
      disabled: props.disabled,
      'onUpdate:modelValue': (value: string | number) => { emit('update:modelValue', value); emit('change', value) },
    }, { default: item })
  },
})
const RadioButton = defineComponent({
  name: 'RRadioButton',
  inheritAttrs: false,
  props: { modelValue: { type: [String, Number] as PropType<string | number>, default: '' }, value: { type: [String, Number] as PropType<string | number>, default: '' }, label: String, disabled: Boolean },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    const inGroup = inject<boolean>(radioGroupContext, false)
    const item = () => primitive(RRadioGroupItem, { ...attrs, value: props.value, disabled: props.disabled, class: ['r-radio-button', attrs.class] }, () => slots.default ? renderSlot(slots, 'default') : props.label)
    return () => inGroup ? item() : primitive(RRadioGroupRoot, {
      modelValue: props.modelValue,
      disabled: props.disabled,
      'onUpdate:modelValue': (value: string | number) => { emit('update:modelValue', value); emit('change', value) },
    }, { default: item })
  },
})
const Result = defineComponent({
  name: 'RResult',
  props: { title: String, subTitle: String, icon: String },
  setup(props, { attrs, slots }) {
    return () => h('section', { ...attrs, class: ['r-result', attrs.class] }, [
      h('div', { class: 'r-result__icon', 'aria-hidden': 'true' }, renderSlot(slots, 'icon', {}, () => [props.icon ?? '✓'] )),
      props.title ? h('h2', { class: 'r-result__title' }, props.title) : null,
      props.subTitle ? h('p', { class: 'r-result__subtitle' }, props.subTitle) : null,
      slots.extra ? h('div', { class: 'r-result__extra' }, renderSlot(slots, 'extra')) : null,
    ])
  },
})
const Row = defineComponent({
  name: 'RRow',
  inheritAttrs: false,
  props: { gutter: { type: [Number, String], default: 0 }, align: String, justify: String },
  setup(props, { attrs, slots }) {
    return () => h('div', {
      ...attrs,
      class: ['r-row', attrs.class],
      style: [{ gap: `${Number(props.gutter) || 0}px`, alignItems: props.align, justifyContent: props.justify }, attrs.style],
    }, renderSlot(slots, 'default'))
  },
})
const Scrollbar = defineComponent({
  name: 'RScrollbar',
  inheritAttrs: false,
  props: { height: [String, Number], maxHeight: [String, Number], always: Boolean },
  setup(props, { attrs, slots }) {
    const size = (value?: string | number) => typeof value === 'number' ? `${value}px` : value
    return () => primitive(RScrollAreaRoot, {
      ...attrs,
      class: ['r-scrollbar', attrs.class],
      style: [{ height: size(props.height), maxHeight: size(props.maxHeight) }, attrs.style],
    }, {
      default: () => [
        primitive(RScrollAreaViewport, { class: 'r-scrollbar__viewport' }, () => renderSlot(slots, 'default')),
        primitive(RScrollAreaScrollbar, { class: 'r-scrollbar__track', orientation: 'vertical', forceMount: props.always || undefined }, () => primitive(RScrollAreaThumb, { class: 'r-scrollbar__thumb' })),
        primitive(RScrollAreaScrollbar, { class: 'r-scrollbar__track r-scrollbar__track--horizontal', orientation: 'horizontal', forceMount: props.always || undefined }, () => primitive(RScrollAreaThumb, { class: 'r-scrollbar__thumb' })),
        primitive(RScrollAreaCorner),
      ],
    })
  },
})

const Segmented = defineComponent({
  name: 'RSegmented',
  inheritAttrs: false,
  props: {
    modelValue: { type: [String, Number] as PropType<string | number>, default: '' },
    options: { type: Array as PropType<Array<string | number | { label: string; value: string | number; disabled?: boolean }>>, default: () => [] },
    disabled: Boolean,
  },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit }) {
    return () => primitive(RToggleGroupRoot, {
      ...attrs,
      type: 'single',
      modelValue: props.modelValue === '' ? '' : String(props.modelValue),
      disabled: props.disabled,
      class: ['r-segmented', attrs.class],
      'onUpdate:modelValue': (id: string) => {
        const option = props.options.map((item) => typeof item === 'object' ? item : { label: String(item), value: item }).find((item) => String(item.value) === id)
        if (option) { emit('update:modelValue', option.value); emit('change', option.value) }
      },
    }, {
      default: () => props.options.map((option) => {
        const item = typeof option === 'object' ? option : { label: String(option), value: option }
        return primitive(RToggleGroupItem, {
          key: String(item.value),
          value: String(item.value),
          disabled: props.disabled || item.disabled,
          class: 'r-segmented__item',
        }, () => item.label)
      }),
    })
  },
})

const SelectOption = Option
interface SelectEntry { id: string; value: string | number; label: string; disabled: boolean }

function isOptionNode(node: VNode): boolean {
  if (!node) return false
  if (node.type === Option || node.type === SelectOption) return true
  if (typeof node.type === 'object' && node.type !== null) {
    const name = (node.type as any).name
    if (name === 'ROption' || name === 'RSelectOption' || name === 'Option') return true
  }
  return false
}

function collectOptions(nodes: unknown, output: VNode[] = []): VNode[] {
  if (Array.isArray(nodes)) {
    for (const child of nodes) collectOptions(child, output)
    return output
  }
  if (!isVNode(nodes)) return output
  if (isOptionNode(nodes)) {
    output.push(nodes)
    return output
  }
  if (nodes.type === Fragment && Array.isArray(nodes.children)) {
    collectOptions(nodes.children, output)
  } else if (Array.isArray(nodes.children)) {
    collectOptions(nodes.children, output)
  }
  return output
}

const Select = defineComponent({
  name: 'RSelect',
  inheritAttrs: false,
  props: {
    modelValue: { type: [String, Number] as PropType<string | number | undefined>, default: undefined },
    placeholder: { type: String, default: 'Select' },
    disabled: Boolean,
    clearable: Boolean,
    filterable: Boolean,
  },
  emits: ['update:modelValue', 'change', 'clear'],
  setup(props, { attrs, emit, slots }) {
    return () => {
      const optionNodes = collectOptions(slots.default?.() ?? emptySlot())
      const entries: SelectEntry[] = optionNodes.map((node, index) => {
        const rawValue = vnodeProp(node, 'value')
        const val = rawValue !== undefined && rawValue !== null ? (rawValue as string | number) : ''
        const rawLabel = vnodeProp(node, 'label')
        const txt = vnodeText(node).trim()
        const label = rawLabel !== undefined && rawLabel !== null ? String(rawLabel) : (txt || String(val))
        return {
          id: `r-opt-${index}`,
          value: val,
          label,
          disabled: Boolean(vnodeProp(node, 'disabled')),
        }
      })

      const selected = entries.find((entry) => {
        if (props.modelValue === undefined || props.modelValue === null) return false
        if (Object.is(entry.value, props.modelValue)) return true
        return String(entry.value) === String(props.modelValue)
      })

      return primitive(RSelectRoot, {
        modelValue: selected ? selected.id : undefined,
        disabled: props.disabled,
        'onUpdate:modelValue': (id: string) => {
          const entry = entries.find((candidate) => candidate.id === id)
          if (entry) {
            emit('update:modelValue', entry.value)
            emit('change', entry.value)
          }
        },
      }, {
        default: () => [
          h('span', {
            class: ['r-select__control', attrs.class],
            style: attrs.style,
          }, [
            primitive(RSelectTrigger, {
              class: 'r-select__trigger',
              'aria-label': (attrs['aria-label'] as string) || props.placeholder,
              disabled: props.disabled,
            }, {
              default: () => [
                primitive(RSelectValue, { placeholder: props.placeholder }, () => (selected ? selected.label : (props.placeholder || ''))),
                h('span', { class: 'r-select__chevron', 'aria-hidden': 'true' }, '▾'),
              ],
            }),
            props.clearable && !props.disabled && props.modelValue !== undefined && props.modelValue !== '' ? h('button', {
              type: 'button',
              class: 'r-select__clear',
              'aria-label': 'Clear selection',
              onClick: (event: Event) => {
                event.stopPropagation()
                emit('update:modelValue', '')
                emit('change', '')
                emit('clear')
              },
            }, '×') : null,
          ]),
          primitive(RSelectPortal, null, {
            default: () => primitive(RSelectContent, {
              class: 'r-select__content',
              position: 'popper',
              sideOffset: 4,
            }, {
              default: () => primitive(RSelectViewport, { class: 'r-select__viewport' }, entries.map((entry) => primitive(RSelectItem, {
                key: entry.id,
                value: entry.id,
                disabled: entry.disabled,
                class: 'r-select__item',
              }, {
                default: () => primitive(RSelectItemText, null, () => entry.label),
              }))),
            }),
          }),
        ],
      })
    }
  },
})

const Statistic = defineComponent({
  name: 'RStatistic',
  props: { title: String, value: [String, Number], precision: Number, prefix: String, suffix: String },
  setup(props, { attrs, slots }) {
    return () => h('div', { ...attrs, class: ['r-statistic', attrs.class] }, [
      h('div', { class: 'r-statistic__title' }, renderSlot(slots, 'title', {}, () => [props.title ?? ''])),
      h('div', { class: 'r-statistic__value' }, [
        props.prefix ? h('span', { class: 'r-statistic__prefix' }, props.prefix) : null,
        props.value,
        props.suffix ? h('span', { class: 'r-statistic__suffix' }, props.suffix) : null,
      ]),
    ])
  },
})
const Step = defineComponent({
  name: 'RStep',
  props: { title: String, description: String, status: String, icon: String },
  setup(props, { attrs, slots }) {
    return () => h('li', { ...attrs, class: ['r-step', props.status ? `r-step--${props.status}` : '', attrs.class] }, [
      h('span', { class: 'r-step__marker', 'aria-hidden': 'true' }, props.icon ?? '•'),
      h('div', { class: 'r-step__copy' }, [h('strong', { class: 'r-step__title' }, props.title), h('p', { class: 'r-step__description' }, renderSlot(slots, 'description', {}, () => [props.description ?? '']))]),
    ])
  },
})
const Steps = defineComponent({
  name: 'RSteps',
  inheritAttrs: false,
  props: { active: { type: Number, default: 0 }, finishStatus: { type: String, default: 'finish' }, simple: Boolean },
  setup(props, { attrs, slots }) {
    return () => {
      const nodes = collectVNodes(slots.default?.() ?? emptySlot()).filter((node) => node.type === Step)
      return h('ol', { ...attrs, class: ['r-steps', props.simple ? 'r-steps--simple' : '', attrs.class] }, nodes.map((node, index) => {
        const title = vnodeProp(node, 'title')
        const description = vnodeProp(node, 'description')
        const icon = vnodeProp(node, 'icon')
        const status = index < props.active ? props.finishStatus : index === props.active ? 'process' : 'wait'
        return h('li', { key: index, class: ['r-step', `r-step--${status}`] }, [
          h('span', { class: 'r-step__marker', 'aria-hidden': 'true' }, String(icon ?? index + 1)),
          h('div', { class: 'r-step__copy' }, [h('strong', { class: 'r-step__title' }, String(title ?? '')), description ? h('p', { class: 'r-step__description' }, String(description)) : null]),
        ])
      }))
    }
  },
})

const Switch = defineComponent({
  name: 'RSwitch',
  inheritAttrs: false,
  props: {
    modelValue: { type: [Boolean, String, Number] as PropType<boolean | string | number>, default: false },
    activeValue: { type: [Boolean, String, Number] as PropType<boolean | string | number>, default: true },
    inactiveValue: { type: [Boolean, String, Number] as PropType<boolean | string | number>, default: false },
    activeText: String,
    inactiveText: String,
    disabled: Boolean,
    name: String,
  },
  emits: ['update:modelValue', 'change'],
  setup(props, { attrs, emit, slots }) {
    const checked = computed(() => Object.is(props.modelValue, props.activeValue))
    const toggle = () => {
      if (props.disabled) return
      const next = checked.value ? props.inactiveValue : props.activeValue
      emit('update:modelValue', next)
      emit('change', next)
    }
    return () => {
      const labelText = checked.value
        ? (props.activeText || '')
        : (props.inactiveText || props.activeText || '')
      const hasLabel = Boolean(slots.default || labelText)

      return h('label', {
        ...attrs,
        class: [
          'r-switch-wrap',
          props.disabled ? 'is-disabled' : '',
          checked.value ? 'is-checked' : '',
          attrs.class,
        ],
        onClick: (event: MouseEvent) => {
          if ((event.target as HTMLElement).closest('.r-switch')) return
          event.preventDefault()
          toggle()
        },
      }, [
        primitive(RSwitchRoot, {
          type: 'button',
          checked: checked.value,
          modelValue: checked.value,
          disabled: props.disabled,
          name: props.name,
          class: 'r-switch',
          'aria-checked': checked.value,
          'onUpdate:modelValue': (value: boolean) => {
            const next = value ? props.activeValue : props.inactiveValue
            emit('update:modelValue', next)
            emit('change', next)
          },
        }, {
          default: () => [primitive(RSwitchThumb, { class: 'r-switch__thumb' })],
        }),
        hasLabel ? h('span', { class: 'r-switch__label' }, slots.default ? renderSlot(slots, 'default') : labelText) : null,
      ])
    }
  },
})

const TabPane = defineComponent({ name: 'RTabPane', setup: () => () => null })
const Tabs = defineComponent({
  name: 'RTabs',
  inheritAttrs: false,
  props: { modelValue: { type: [String, Number] as PropType<string | number>, default: '' }, type: String, orientation: { type: String, default: 'horizontal' } },
  emits: ['update:modelValue', 'tab-change'],
  setup(props, { attrs, emit, slots }) {
    return () => {
      const panes = collectVNodes(slots.default?.() ?? emptySlot()).filter((node) => node.type === TabPane).map((node, index) => ({
        node,
        value: String(vnodeProp(node, 'name') ?? index),
        original: vnodeProp(node, 'name') ?? String(index),
        label: vnodeProp(node, 'label') ?? vnodeText(node),
      }))
      const active = panes.find((pane) => Object.is(pane.original, props.modelValue)) ?? panes.find((pane) => pane.value === String(props.modelValue))
      return primitive(RTabsRoot, {
        ...attrs,
        modelValue: active?.value ?? String(props.modelValue),
        orientation: props.orientation,
        class: ['r-tabs', props.type ? `r-tabs--${props.type}` : '', attrs.class],
        'onUpdate:modelValue': (value: string) => {
          const pane = panes.find((candidate) => candidate.value === value)
          const next = pane?.original ?? value
          emit('update:modelValue', next)
          emit('tab-change', next)
        },
      }, {
        default: () => [
          primitive(RTabsList, { class: 'r-tabs__list' }, () => panes.map((pane) => primitive(RTabsTrigger, {
            key: pane.value,
            value: pane.value,
            class: 'r-tabs__trigger',
          }, () => pane.label as VNodeChild))),
          ...panes.map((pane) => primitive(RTabsContent, { key: pane.value, value: pane.value, class: 'r-tabs__content' }, () => vnodeSlot(pane.node))),
        ],
      })
    }
  },
})

const TableColumn = defineComponent({ name: 'RTableColumn', setup: () => () => null })
function readPath(row: unknown, path: string): unknown {
  return path.split('.').reduce<unknown>((value, key) => value && typeof value === 'object' ? (value as Record<string, unknown>)[key] : undefined, row)
}
const Table = defineComponent({
  name: 'RTable',
  inheritAttrs: false,
  props: {
    data: { type: Array as PropType<unknown[]>, default: () => [] },
    border: Boolean,
    stripe: Boolean,
    loading: Boolean,
    rowKey: { type: [String, Function] as PropType<string | ((row: unknown) => string | number)>, default: 'id' },
    emptyText: { type: String, default: 'No data' },
  },
  emits: ['selection-change', 'select', 'select-all'],
  setup(props, { attrs, slots, emit }) {
    const selectedKeys = ref(new Set<string>())
    const rowKey = (row: unknown, index: number) => {
      if (typeof props.rowKey === 'function') return String(props.rowKey(row))
      const value = props.rowKey && readPath(row, props.rowKey)
      return String(value ?? index)
    }
    const selectedRows = () => props.data.filter((row, index) => selectedKeys.value.has(rowKey(row, index)))
    const notifySelection = (row?: unknown) => {
      const rows = selectedRows()
      emit('selection-change', rows)
      if (row !== undefined) emit('select', rows, row)
    }
    const toggleRow = (row: unknown, index: number, checked: boolean) => {
      const key = rowKey(row, index)
      if (checked) selectedKeys.value.add(key)
      else selectedKeys.value.delete(key)
      notifySelection(row)
    }
    const toggleAll = (checked: boolean) => {
      selectedKeys.value = new Set(checked ? props.data.map(rowKey) : [])
      const rows = selectedRows()
      emit('selection-change', rows)
      emit('select-all', rows)
    }
    watch(() => props.data, () => { selectedKeys.value = new Set(); emit('selection-change', []) })
    return () => {
      const columns = collectVNodes(slots.default?.() ?? emptySlot()).filter((node) => node.type === TableColumn)
      const allSelected = props.data.length > 0 && props.data.every((row, index) => selectedKeys.value.has(rowKey(row, index)))
      return h('div', { ...attrs, class: ['r-table-wrap', attrs.class], 'aria-busy': props.loading || undefined }, [
        h('table', { class: ['r-table', props.border ? 'r-table--border' : '', props.stripe ? 'r-table--stripe' : ''] }, [
          h('thead', null, h('tr', null, columns.map((column, index) => {
            const width = toCssUnit(vnodeProp(column, 'width'))
            const minWidth = toCssUnit(vnodeProp(column, 'min-width', 'minWidth'))
            const isSelection = vnodeProp(column, 'type') === 'selection'
            return h('th', {
              key: index,
              scope: 'col',
              class: [`r-table__cell--${String(vnodeProp(column, 'align') ?? 'left')}`, vnodeProp(column, 'fixed') ? 'r-table__cell--fixed' : ''],
              style: { width, minWidth },
            }, isSelection ? h('input', { type: 'checkbox', class: 'r-table__checkbox', checked: allSelected, disabled: props.loading || !props.data.length, 'aria-label': '全选当前页', onChange: (event: Event) => toggleAll((event.target as HTMLInputElement).checked) }) : [vnodeProp(column, 'label') as VNodeChild ?? ''])
          }))),
          h('tbody', null, props.data.length ? props.data.map((row, rowIndex) => h('tr', { key: rowKey(row, rowIndex) }, columns.map((column, columnIndex) => {
            const width = toCssUnit(vnodeProp(column, 'width'))
            const minWidth = toCssUnit(vnodeProp(column, 'min-width', 'minWidth'))
            const prop = vnodeProp(column, 'prop')
            const isSelection = vnodeProp(column, 'type') === 'selection'
            const slot = (column.children as Record<string, unknown> | null)?.default
            const content = isSelection
              ? h('input', { type: 'checkbox', class: 'r-table__checkbox', checked: selectedKeys.value.has(rowKey(row, rowIndex)), 'aria-label': `选择第 ${rowIndex + 1} 行`, onChange: (event: Event) => toggleRow(row, rowIndex, (event.target as HTMLInputElement).checked) })
              : typeof slot === 'function'
                ? (slot as (scope: { row: unknown; $index: number }) => VNodeChild[])({ row, $index: rowIndex })
                : prop ? readPath(row, String(prop)) as VNodeChild : ''
            return h('td', {
              key: columnIndex,
              class: [`r-table__cell--${String(vnodeProp(column, 'align') ?? 'left')}`, vnodeProp(column, 'fixed') ? 'r-table__cell--fixed' : ''],
              style: { width, minWidth },
            }, [content as VNodeChild])
          }))) : h('tr', null, h('td', { class: 'r-table__empty', colspan: Math.max(1, columns.length) }, props.emptyText))),
        ]),
        props.loading ? h('div', { class: 'r-table__loading', role: 'status', 'aria-label': 'Loading' }, h('span', { class: 'r-spinner' })) : null,
      ])
    }
  },
})

const Tag = defineComponent({
  name: 'RTag',
  props: { type: { type: String, default: 'default' }, closable: Boolean, effect: String, size: String },
  emits: ['close'],
  setup(props, { attrs, emit, slots }) {
    return () => h('span', { ...attrs, class: ['r-tag', `r-tag--${props.type}`, props.effect ? `r-tag--${props.effect}` : '', props.size ? `r-tag--${props.size}` : '', attrs.class] }, [
      renderSlot(slots, 'default'),
      props.closable ? h('button', { type: 'button', class: 'r-tag__close', 'aria-label': 'Remove', onClick: (event: MouseEvent) => { event.stopPropagation(); emit('close', event) } }, '×') : null,
    ])
  },
})
const Tooltip = defineComponent({
  name: 'RTooltip',
  props: { content: String, side: { type: String, default: undefined }, placement: String, delayDuration: { type: Number, default: 300 } },
  setup(props, { attrs, slots }) {
    const side = computed(() => props.side ?? props.placement ?? 'top')
    return () => primitive(RTooltipProvider, { delayDuration: props.delayDuration }, {
      default: () => primitive(RTooltipRoot, null, {
        default: () => [
          primitive(RTooltipTrigger, { ...attrs, asChild: true }, { default: () => renderSlot(slots, 'default') }),
          primitive(RTooltipPortal, null, { default: () => primitive(RTooltipContent, { class: 'r-tooltip', side: side.value, sideOffset: 6 }, () => props.content ?? renderSlot(slots, 'content')) }),
        ],
      }),
    })
  },
})

const Upload = defineComponent({
  name: 'RUpload',
  inheritAttrs: false,
  props: { accept: String, disabled: Boolean, multiple: Boolean },
  emits: ['change', 'update:modelValue'],
  setup(props, { attrs, emit, slots }) {
    const input = ref<HTMLInputElement>()
    const onChange = (event: Event) => {
      const target = event.target as HTMLInputElement
      const file = target.files?.[0]
      if (file) {
        const item = { raw: file, name: file.name, size: file.size }
        emit('change', item)
        emit('update:modelValue', item)
      }
      target.value = ''
    }
    return () => h('label', { ...attrs, class: ['r-upload', props.disabled ? 'is-disabled' : '', attrs.class] }, [
      renderSlot(slots, 'default', {}, () => [h('span', { class: 'r-upload__trigger' }, 'Choose file')]),
      h('input', {
        ref: input,
        class: 'r-upload__input',
        type: 'file',
        accept: props.accept,
        disabled: props.disabled,
        multiple: props.multiple,
        onChange,
      }),
    ])
  },
})

const componentMap: Record<string, Component> = {
  'r-config-provider': ConfigProvider,
  'r-alert': Alert,
  'r-avatar': Avatar,
  'r-badge': Badge,
  'r-button': Button,
  'r-button-group': ButtonGroup,
  'r-card': Card,
  'r-checkbox': Checkbox,
  'r-checkbox-group': CheckboxGroup,
  'r-col': Col,
  'r-collapse': Collapse,
  'r-collapse-item': CollapseItem,
  'r-date-picker': DatePicker,
  'r-descriptions': Descriptions,
  'r-descriptions-item': DescriptionsItem,
  'r-dialog': Dialog,
  'r-divider': Divider,
  'r-drawer': Drawer,
  'r-dropdown': Dropdown,
  'r-dropdown-item': DropdownItem,
  'r-dropdown-menu': DropdownMenu,
  'r-empty': Empty,
  'r-form': Form,
  'r-form-item': FormItem,
  'r-icon': Icon,
  'r-image': Image,
  'r-input': Input,
  'r-input-number': InputNumber,
  'r-link': Link,
  'r-option': Option,
  'r-pagination': Pagination,
  'r-radio': Radio,
  'r-radio-button': RadioButton,
  'r-radio-group': RadioGroup,
  'r-result': Result,
  'r-row': Row,
  'r-scrollbar': Scrollbar,
  'r-segmented': Segmented,
  'r-select': Select,
  'r-select-option': Option,
  'r-statistic': Statistic,
  'r-step': Step,
  'r-steps': Steps,
  'r-switch': Switch,
  'r-tab-pane': TabPane,
  'r-table': Table,
  'r-table-column': TableColumn,
  'r-tabs': Tabs,
  'r-tag': Tag,
  'r-tooltip': Tooltip,
  'r-upload': Upload,
}


const loadingNodes = new WeakMap<HTMLElement, { overlay: HTMLDivElement; position: string; addedClass: boolean }>()
function setLoading(el: HTMLElement, active: boolean) {
  const existing = loadingNodes.get(el)
  if (active && !existing) {
    const position = el.style.position
    const addedClass = !el.classList.contains('r-loading-host')
    el.classList.add('r-loading-host')
    const overlay = document.createElement('div')
    overlay.className = 'r-loading-overlay'
    overlay.setAttribute('role', 'status')
    overlay.setAttribute('aria-label', 'Loading')
    const spinner = document.createElement('span')
    spinner.className = 'r-spinner'
    overlay.appendChild(spinner)
    el.appendChild(overlay)
    loadingNodes.set(el, { overlay, position, addedClass })
  } else if (!active && existing) {
    existing.overlay.remove()
    if (existing.addedClass) el.classList.remove('r-loading-host')
    el.style.position = existing.position
    loadingNodes.delete(el)
  }
}

export const loadingDirective: Directive<HTMLElement, boolean | string> = {
  mounted(el, binding) { setLoading(el, Boolean(binding.value)) },
  updated(el, binding) { setLoading(el, Boolean(binding.value)) },
  unmounted(el) { setLoading(el, false) },
}

export const RadixUiPlugin: Plugin = {
  install(app: App) {
    // 基础组件样式已固化为静态样式表（src/styles/radix-base.css，由 main.ts 引入），
    // 此处不再运行时注入 <style>，避免缓存 / CSP 等场景下样式缺失导致组件退化。
    for (const [name, component] of Object.entries(componentMap)) app.component(name, component)
    app.directive('loading', loadingDirective)
  },
}
