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
      props.loading ? h('span', { class: 'r-spinner', 'aria-hidden': 'true' }) : props.icon ? typeof props.icon === 'string' ? h('span', { class: `r-button__status-icon r-button__status-icon--${props.icon}`, 'aria-hidden': 'true' }, props.icon === 'success' ? '✓' : props.icon === 'error' ? '×' : props.icon) : h(props.icon as Component, { size: 16, 'aria-hidden': 'true' }) : null,
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
const Option = defineComponent({ name: 'ROption', setup: () => () => null })

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

const SelectOption = defineComponent({ name: 'RSelectOption', setup: () => () => null })
interface SelectEntry { id: string; value: string | number; label: string; disabled: boolean }
const Select = defineComponent({
  name: 'RSelect',
  inheritAttrs: false,
  props: {
    modelValue: { type: [String, Number] as PropType<string | number | undefined>, default: undefined },
    placeholder: { type: String, default: 'Select' },
    disabled: Boolean,
    clearable: Boolean,
  },
  emits: ['update:modelValue', 'change', 'clear'],
  setup(props, { attrs, emit, slots }) {
    return () => {
      const entries: SelectEntry[] = collectVNodes(slots.default?.() ?? emptySlot())
        .filter((node) => node.type === SelectOption)
        .map((node, index) => ({
          id: `r-option-${index}`,
          value: (vnodeProp(node, 'value') ?? '') as string | number,
          label: String(vnodeProp(node, 'label') ?? vnodeText(node)),
          disabled: Boolean(vnodeProp(node, 'disabled')),
        }))
      const selected = entries.find((entry) => Object.is(entry.value, props.modelValue))
      return primitive(RSelectRoot, {
        modelValue: selected?.id,
        disabled: props.disabled,
        'onUpdate:modelValue': (id: string) => {
          const entry = entries.find((candidate) => candidate.id === id)
          if (entry) { emit('update:modelValue', entry.value); emit('change', entry.value) }
        },
      }, {
        default: () => [
          h('span', { class: 'r-select__control' }, [
            primitive(RSelectTrigger, { ...attrs, class: ['r-select__trigger', attrs.class], 'aria-label': attrs['aria-label'] }, {
              default: () => [primitive(RSelectValue, { placeholder: props.placeholder }), h('span', { class: 'r-select__chevron', 'aria-hidden': 'true' }, '▾')],
            }),
            props.clearable && props.modelValue !== undefined && props.modelValue !== '' ? h('button', { type: 'button', class: 'r-select__clear', 'aria-label': 'Clear selection', onClick: (event: Event) => { event.stopPropagation(); emit('update:modelValue', ''); emit('change', ''); emit('clear') } }, '×') : null,
          ]),
          primitive(RSelectPortal, null, {
            default: () => primitive(RSelectContent, { class: 'r-select__content', position: 'popper', sideOffset: 4 }, {
              default: () => primitive(RSelectViewport, { class: 'r-select__viewport' }, entries.map((entry) => primitive(RSelectItem, {
                key: entry.id,
                value: entry.id,
                disabled: entry.disabled,
                class: 'r-select__item',
              }, { default: () => primitive(RSelectItemText, null, () => entry.label) }))),
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
    return () => primitive(RSwitchRoot, {
      ...attrs,
      type: 'button',
      modelValue: checked.value,
      disabled: props.disabled,
      name: props.name,
      class: ['r-switch', attrs.class],
      'onUpdate:modelValue': (value: boolean) => {
        const next = value ? props.activeValue : props.inactiveValue
        emit('update:modelValue', next)
        emit('change', next)
      },
    }, {
      default: () => [primitive(RSwitchThumb, { class: 'r-switch__thumb' }), slots.default || props.activeText || props.inactiveText ? h('span', { class: 'r-switch__label' }, slots.default ? renderSlot(slots, 'default') : (checked.value ? props.activeText : props.inactiveText)) : null],
    })
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
            const width = vnodeProp(column, 'width')
            const minWidth = vnodeProp(column, 'min-width', 'minWidth')
            const isSelection = vnodeProp(column, 'type') === 'selection'
            return h('th', {
              key: index,
              scope: 'col',
              class: [`r-table__cell--${String(vnodeProp(column, 'align') ?? 'left')}`, vnodeProp(column, 'fixed') ? 'r-table__cell--fixed' : ''],
              style: { width: typeof width === 'number' ? `${width}px` : width, minWidth: typeof minWidth === 'number' ? `${minWidth}px` : minWidth },
            }, isSelection ? h('input', { type: 'checkbox', class: 'r-table__checkbox', checked: allSelected, disabled: props.loading || !props.data.length, 'aria-label': '全选当前页', onChange: (event: Event) => toggleAll((event.target as HTMLInputElement).checked) }) : [vnodeProp(column, 'label') as VNodeChild ?? ''])
          }))),
          h('tbody', null, props.data.length ? props.data.map((row, rowIndex) => h('tr', { key: rowKey(row, rowIndex) }, columns.map((column, columnIndex) => {
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
              style: { width: typeof vnodeProp(column, 'width') === 'number' ? `${vnodeProp(column, 'width')}px` : vnodeProp(column, 'width'), minWidth: typeof vnodeProp(column, 'min-width', 'minWidth') === 'number' ? `${vnodeProp(column, 'min-width', 'minWidth')}px` : vnodeProp(column, 'min-width', 'minWidth') },
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

const styles = `
:root {
  --r-surface: var(--surface, #fff);
  --r-surface-raised: var(--surface, #fff);
  --r-text: var(--text-primary, #1f1f1f);
  --r-muted: var(--text-secondary, #80868b);
  --r-border: var(--border-color, #e8e8ea);
  --r-primary: var(--brand, #1f1f1f);
  --r-primary-contrast: #fff;
  --r-danger: #b42318;
  --r-radius: var(--radius-md, 0.75rem);
  --r-shadow: var(--shadow-pop, 0 12px 32px rgb(15 23 42 / 14%));
}
.r-button,.r-input,.r-select__trigger,.r-pagination__button,.r-segmented__item { font: inherit; }
.r-button { display:inline-flex; align-items:center; justify-content:center; gap:.5rem; border:1px solid var(--r-border); border-radius:var(--r-radius); padding:.55rem .9rem; background:var(--r-surface); color:var(--r-text); cursor:pointer; transition:background .16s,border-color .16s,transform .16s; }
.r-button:hover:not(:disabled) { border-color:var(--r-primary); }
.r-button:active:not(:disabled) { transform:translateY(1px); }
.r-button:disabled,.r-radio-button:disabled { opacity:.55; cursor:not-allowed; }
.r-button--primary { color:var(--r-primary-contrast); background:var(--r-primary); border-color:var(--r-primary); }
.r-button--danger { color:#fff; background:var(--r-danger); border-color:var(--r-danger); }.r-button--success { color:#fff; background:#16803c; border-color:#16803c; }.r-button--warning { color:#1f1f1f; background:#f4c542; border-color:#f4c542; }
.r-button--plain { background:transparent; }.r-button--plain.r-button--primary { color:var(--r-primary); }.r-button--plain.r-button--danger { color:var(--r-danger); }.r-button--plain.r-button--warning { color:#9a6500; }.r-button--circle { border-radius:50%; padding:.55rem; }.r-button--round { border-radius:999px; }
.r-button--text,.r-button--link { border-color:transparent; background:transparent; color:var(--r-primary); }
.r-button--small { padding:.35rem .65rem; font-size:.875em; }
.r-button--large { padding:.75rem 1.1rem; font-size:1.05em; }
.r-button-group { display:inline-flex; align-items:center; }
.r-button-group > .r-button:not(:first-child) { margin-inline-start:-1px; border-start-start-radius:0; border-end-start-radius:0; }
.r-button-group > .r-button:not(:last-child) { border-start-end-radius:0; border-end-end-radius:0; }
.r-card { overflow:hidden; border:1px solid var(--r-border); border-radius:var(--r-radius); background:var(--r-surface-raised); color:var(--r-text); }
.r-card--always { box-shadow:var(--r-shadow); }
.r-card__header,.r-card__footer { padding:.85rem 1rem; border-bottom:1px solid var(--r-border); font-weight:600; }
.r-card__footer { border:0; border-top:1px solid var(--r-border); }
.r-card__body { padding:1rem; }
.r-alert { display:flex; align-items:flex-start; justify-content:space-between; gap:1rem; padding:.8rem 1rem; border:1px solid var(--r-border); border-radius:var(--r-radius); background:var(--r-surface); color:var(--r-text); }
.r-alert--success { border-color:#86efac; background:#f0fdf4; }.r-alert--warning { border-color:#fcd34d; background:#fffbeb; }.r-alert--error,.r-alert--danger { border-color:#fca5a5; background:#fef2f2; }
.r-alert__icon { display:grid; width:1.3rem; height:1.3rem; flex:none; place-items:center; border:1px solid currentColor; border-radius:50%; font-weight:700; }.r-alert__title { display:block; margin-bottom:.2rem; }.r-alert__description { color:var(--r-muted); }.r-alert__close,.r-dialog__close { border:0; background:transparent; color:var(--r-muted); font-size:1.25rem; cursor:pointer; }
.r-avatar { display:inline-flex; width:2.5rem; height:2.5rem; align-items:center; justify-content:center; overflow:hidden; border-radius:50%; background:#eef2ff; color:var(--r-primary); font-weight:600; }.r-avatar img { width:100%; height:100%; object-fit:cover; }.r-avatar--small { width:2rem;height:2rem; }.r-avatar--large { width:3.5rem;height:3.5rem; }
.r-badge-wrap { position:relative; display:inline-flex; }.r-badge { position:absolute; inset-block-start:-.55rem; inset-inline-end:-.65rem; min-width:1.15rem; padding:.1rem .3rem; border-radius:999px; background:var(--r-primary); color:#fff; font-size:.7rem; line-height:1.2; text-align:center; }.r-badge--danger { background:var(--r-danger); }.r-badge--success { background:#16a34a; }.r-badge--warning { background:#d97706; }
.r-checkbox,.r-radio { display:inline-flex; align-items:center; gap:.5rem; color:var(--r-text); cursor:pointer; }.r-checkbox__indicator,.r-radio__indicator { display:inline-flex; width:1.1rem; height:1.1rem; align-items:center; justify-content:center; border:1px solid var(--r-border); border-radius:.3rem; background:var(--r-surface); color:#fff; font-size:.75rem; }.r-checkbox[data-state=checked] .r-checkbox__indicator { border-color:var(--r-primary); background:var(--r-primary); }.r-checkbox-group,.r-radio-group { display:flex; flex-wrap:wrap; gap:.8rem 1rem; }.r-radio__indicator { border-radius:50%; color:var(--r-primary); font-size:.65rem; }.r-radio-button { border:1px solid var(--r-border); padding:.5rem .85rem; background:var(--r-surface); cursor:pointer; }.r-radio-button[data-state=checked] { border-color:var(--r-primary); color:var(--r-primary); background:#eef2ff; }
.r-row { display:grid; grid-template-columns:repeat(24,minmax(0,1fr)); }.r-col { min-width:0; grid-column:span 24; }${Array.from({ length: 24 }, (_, index) => `.r-col--xs-${index + 1}{grid-column:span ${index + 1}}`).join('')}@media(min-width:640px){${Array.from({ length: 24 }, (_, index) => `.r-col--sm-${index + 1}{grid-column:span ${index + 1}}`).join('')}}@media(min-width:768px){${Array.from({ length: 24 }, (_, index) => `.r-col--md-${index + 1}{grid-column:span ${index + 1}}`).join('')}}@media(min-width:1024px){${Array.from({ length: 24 }, (_, index) => `.r-col--lg-${index + 1}{grid-column:span ${index + 1}}`).join('')}}@media(min-width:1280px){${Array.from({ length: 24 }, (_, index) => `.r-col--xl-${index + 1}{grid-column:span ${index + 1}}`).join('')}}.r-divider { display:flex; align-items:center; gap:.8rem; margin:1rem 0; color:var(--r-muted); }.r-divider::before,.r-divider::after { flex:1; border-top:1px solid var(--r-border); content:""; }.r-divider--vertical { display:inline-flex; height:1em; margin:0 .7rem; border-inline-start:1px solid var(--r-border); }
.r-form__fieldset { min-width:0; margin:0; padding:0; border:0; }.r-form--inline { display:flex; align-items:flex-end; gap:.75rem; flex-wrap:wrap; }.r-form-item--inline { display:flex; align-items:center; gap:.65rem; margin:0; }.r-form-item--inline .r-form-item__label { margin:0; }.r-form--labels-top .r-form-item__label,.r-form-item--top .r-form-item__label { width:auto !important; }
.r-input-wrap { position:relative; display:flex; align-items:center; gap:.5rem; width:100%; }.r-input-wrap--textarea { align-items:flex-start; }.r-input__prefix,.r-input__suffix { display:inline-flex; align-items:center; color:var(--r-muted); }.r-input__clear,.r-select__clear { position:absolute; inset-inline-end:.5rem; top:50%; transform:translateY(-50%); border:0; background:transparent; color:var(--r-muted); cursor:pointer; }.r-input__limit { position:absolute; inset-inline-end:.6rem; inset-block-end:.35rem; color:var(--r-muted); font-size:.72rem; }.r-input-wrap > .r-input { min-width:0; flex:1; }.r-input-wrap:has(.r-input__limit) > .r-input { padding-bottom:1.4rem; }.r-input--textarea { resize:vertical; }.r-select__control { position:relative; display:inline-flex; width:100%; align-items:center; }.r-select__control .r-select__trigger { padding-inline-end:2.2rem; }.r-select__clear { z-index:2; inset-inline-end:2rem; }
.r-input,.r-select__trigger { width:100%; min-height:2.55rem; padding:.55rem .75rem; border:1px solid var(--r-border); border-radius:var(--r-radius); background:var(--r-surface); color:var(--r-text); outline:none; }.r-input:focus,.r-select__trigger:focus-visible { border-color:var(--r-primary); box-shadow:0 0 0 3px color-mix(in srgb,var(--r-primary) 18%,transparent); }.r-input:disabled { opacity:.6; cursor:not-allowed; }.r-form-item { margin-bottom:1rem; }.r-form-item__label { display:block; margin-bottom:.4rem; color:var(--r-text); font-weight:500; }.r-required,.r-form-item__error { color:var(--r-danger); }.r-form-item__error { margin-top:.3rem; font-size:.85rem; }
.r-overlay { position:fixed; z-index:1000; inset:0; background:rgb(15 23 42 / 45%); }.r-dialog,.r-drawer { position:fixed; z-index:1001; inset-block-start:50%; inset-inline-start:50%; display:flex; max-width:calc(100vw - 2rem); max-height:calc(100vh - 2rem); flex-direction:column; overflow:auto; transform:translate(-50%,-50%); border:1px solid var(--r-border); border-radius:var(--r-radius); background:var(--r-surface-raised); color:var(--r-text); box-shadow:var(--r-shadow); }.r-dialog__header,.r-drawer__header { display:flex; align-items:center; justify-content:space-between; gap:1rem; padding:1rem 1.2rem; border-bottom:1px solid var(--r-border); }.r-dialog__title { margin:0; font-size:1.1rem; font-weight:650; }.r-dialog__body,.r-drawer__body { padding:1.2rem; overflow:auto; }.r-dialog__footer,.r-drawer__footer { display:flex; justify-content:flex-end; gap:.6rem; padding:.9rem 1.2rem; border-top:1px solid var(--r-border); }.r-drawer { inset-block:0; inset-inline-start:auto; width:min(28rem,100vw); max-width:100vw; max-height:none; border-radius:0; transform:none; }.r-drawer--ltr { inset-inline-start:0; }.r-drawer--rtl { inset-inline-end:0; }.r-drawer--ttb { inset-block-end:auto; inset-inline:0; width:100%; height:min(28rem,100vh); }.r-drawer--btt { inset-block-start:auto; inset-inline:0; width:100%; height:min(28rem,100vh); }
.r-dropdown__trigger { display:inline-flex; }.r-dropdown__content,.r-select__content { z-index:1100; min-width:9rem; padding:.3rem; border:1px solid var(--r-border); border-radius:var(--r-radius); background:var(--r-surface-raised); color:var(--r-text); box-shadow:var(--r-shadow); }.r-dropdown__item,.r-select__item { display:flex; align-items:center; min-height:2.2rem; padding:.45rem .65rem; border-radius:calc(var(--r-radius) - .2rem); outline:none; cursor:pointer; }.r-dropdown__item[data-highlighted],.r-select__item[data-highlighted] { background:color-mix(in srgb,var(--r-primary) 12%,var(--r-surface)); }.r-dropdown__item[data-disabled],.r-select__item[data-disabled] { opacity:.45; cursor:not-allowed; }.r-select__trigger { display:flex; align-items:center; justify-content:space-between; text-align:start; cursor:pointer; }.r-select__viewport { padding:.2rem; }.r-select__chevron { color:var(--r-muted); }
.r-empty { display:flex; min-height:9rem; flex-direction:column; align-items:center; justify-content:center; padding:1.5rem; color:var(--r-muted); text-align:center; }.r-empty__illustration { display:grid; width:4rem; height:4rem; place-items:center; border-radius:50%; background:color-mix(in srgb,var(--r-muted) 10%,transparent); font-size:2rem; }.r-empty__description { margin:.8rem 0 0; }.r-tooltip { z-index:1200; max-width:20rem; padding:.45rem .7rem; border-radius:.4rem; background:#111827; color:#fff; font-size:.85rem; box-shadow:var(--r-shadow); }
.r-pagination { display:flex; align-items:center; gap:.6rem; color:var(--r-text); flex-wrap:wrap; }.r-pagination__button { width:2rem; height:2rem; border:1px solid var(--r-border); border-radius:.4rem; background:var(--r-surface); color:var(--r-text); cursor:pointer; }.r-pagination__button:disabled { opacity:.45; cursor:not-allowed; }.r-pagination__total,.r-pagination__status { color:var(--r-muted); font-size:.88rem; }.r-pagination__size,.r-pagination__jumper input { min-height:2rem; padding:.25rem .45rem; border:1px solid var(--r-border); border-radius:.4rem; background:var(--r-surface); color:var(--r-text); }.r-pagination__jumper { display:inline-flex; align-items:center; gap:.35rem; font-size:.85rem; }.r-pagination__jumper input { width:3.5rem; }.r-segmented { display:inline-flex; gap:.2rem; padding:.2rem; border-radius:var(--r-radius); background:color-mix(in srgb,var(--r-muted) 10%,var(--r-surface)); }.r-segmented__item { border:0; border-radius:calc(var(--r-radius) - .2rem); padding:.45rem .8rem; background:transparent; color:var(--r-muted); cursor:pointer; }.r-segmented__item.is-active { background:var(--r-surface); color:var(--r-text); box-shadow:0 1px 3px rgb(15 23 42 / 12%); }
.r-switch { position:relative; display:inline-flex; width:2.6rem; height:1.5rem; align-items:center; padding:.15rem; border:0; border-radius:999px; background:#cbd5e1; cursor:pointer; transition:background .15s; }.r-switch[data-state=checked] { background:var(--r-primary); }.r-switch:disabled { opacity:.55; cursor:not-allowed; }.r-switch__thumb { display:block; width:1.2rem; height:1.2rem; border-radius:50%; background:#fff; box-shadow:0 1px 3px #0003; transition:transform .15s; }.r-switch[data-state=checked] .r-switch__thumb { transform:translateX(1.1rem); }.r-switch__label { margin-inline-start:.35rem; color:var(--r-text); white-space:nowrap; }
.r-tabs__list { display:flex; gap:.2rem; border-bottom:1px solid var(--r-border); }.r-tabs__trigger { padding:.65rem .9rem; border:0; border-bottom:2px solid transparent; background:transparent; color:var(--r-muted); cursor:pointer; }.r-tabs__trigger[data-state=active] { border-color:var(--r-primary); color:var(--r-primary); }.r-tabs__content { padding:1rem 0; outline:none; }.r-table-wrap { position:relative; overflow:auto; border-radius:var(--r-radius); }.r-table { width:100%; border-collapse:collapse; background:var(--r-surface); color:var(--r-text); text-align:left; }.r-table th,.r-table td { padding:.7rem .8rem; border-bottom:1px solid var(--r-border); }.r-table th { color:var(--r-muted); font-size:.85rem; font-weight:600; }.r-table--border th,.r-table--border td { border:1px solid var(--r-border); }.r-table--stripe tbody tr:nth-child(even) { background:color-mix(in srgb,var(--r-muted) 5%,var(--r-surface)); }.r-table__cell--fixed { position:sticky; right:0; z-index:1; background:var(--r-surface); }.r-table th.r-table__cell--fixed { z-index:2; }.r-table__checkbox { width:1rem; height:1rem; accent-color:var(--r-primary); cursor:pointer; }.r-table__cell--center { text-align:center; }.r-table__cell--right { text-align:right; }.r-table__empty { height:7rem; color:var(--r-muted); text-align:center; }.r-table__loading { position:absolute; inset:0; display:grid; place-items:center; background:color-mix(in srgb,var(--r-surface) 72%,transparent); }
.r-tag { display:inline-flex; align-items:center; gap:.35rem; padding:.2rem .55rem; border:1px solid var(--r-border); border-radius:.35rem; background:var(--r-surface); color:var(--r-text); font-size:.85rem; }.r-tag--primary { border-color:color-mix(in srgb,var(--r-primary) 30%,var(--r-border)); background:color-mix(in srgb,var(--r-primary) 9%,var(--r-surface)); color:var(--r-primary); }.r-tag--success { color:#15803d; background:#f0fdf4; }.r-tag--warning { color:#b45309; background:#fffbeb; }.r-tag--danger { color:var(--r-danger); background:#fef2f2; }.r-tag__close { padding:0; border:0; background:none; color:inherit; cursor:pointer; }.r-upload { position:relative; display:inline-flex; cursor:pointer; }.r-upload.is-disabled { opacity:.55; cursor:not-allowed; }.r-upload__input { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0); white-space:nowrap; clip-path:inset(50%); }.r-upload__trigger { display:inline-flex; align-items:center; min-height:2.4rem; padding:.45rem .8rem; border:1px dashed var(--r-border); border-radius:var(--r-radius); color:var(--r-text); }.r-upload:focus-within .r-upload__trigger { outline:2px solid var(--r-primary); outline-offset:2px; }
.r-scrollbar { position:relative; overflow:hidden; }.r-scrollbar__viewport { width:100%; height:100%; border-radius:inherit; }.r-scrollbar__track { display:flex; width:.55rem; padding:.08rem; touch-action:none; user-select:none; background:transparent; }.r-scrollbar__track--horizontal { width:auto; height:.55rem; flex-direction:column; }.r-scrollbar__thumb { flex:1; border-radius:999px; background:color-mix(in srgb,var(--r-muted) 45%,transparent); }.r-descriptions__title { margin:0 0 .8rem; }.r-descriptions__grid { display:grid; grid-template-columns:repeat(var(--r-description-columns),minmax(0,1fr)); margin:0; }.r-descriptions-item { display:grid; grid-template-columns:minmax(5rem,auto) 1fr; gap:.6rem; padding:.6rem .75rem; border-bottom:1px solid var(--r-border); }.r-descriptions-item__label { color:var(--r-muted); }.r-descriptions-item__content { margin:0; color:var(--r-text); }.r-descriptions--border .r-descriptions-item { border:1px solid var(--r-border); }.r-icon { display:inline-flex; align-items:center; justify-content:center; }.r-image { display:block; max-width:100%; }.r-image--previewable { cursor:zoom-in; }.r-image--error { display:grid; place-items:center; min-width:2rem; min-height:2rem; background:var(--surface-hover); color:var(--text-secondary); }.r-image-preview__overlay { position:fixed; z-index:1300; inset:0; background:rgb(0 0 0 / 85%); }.r-image-preview { position:fixed; z-index:1301; inset:0; display:grid; width:100vw; height:100dvh; place-items:center; background:transparent; outline:0; }.r-image-preview__image { max-width:90vw; max-height:88vh; object-fit:contain; }.r-image-preview__close,.r-image-preview__previous,.r-image-preview__next { position:absolute; display:grid; width:2.8rem; height:2.8rem; place-items:center; border:1px solid rgb(255 255 255 / 25%); border-radius:50%; background:rgb(0 0 0 / 35%); color:white; font-size:1.8rem; cursor:pointer; }.r-image-preview__close { inset-block-start:1.25rem; inset-inline-end:1.5rem; }.r-image-preview__previous { inset-inline-start:2rem; }.r-image-preview__next { inset-inline-end:2rem; }.r-image-preview__count { position:absolute; inset-block-end:1.5rem; color:white; }.r-sr-only { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip:rect(0,0,0,0); white-space:nowrap; border:0; }.r-link { color:var(--r-primary); text-decoration:underline; }.r-link--plain { text-decoration:none; }.r-link[aria-disabled=true] { color:var(--r-muted); cursor:not-allowed; }.r-statistic__title { margin-bottom:.35rem; color:var(--r-muted); font-size:.9rem; }.r-statistic__value { color:var(--r-text); font-size:1.8rem; font-weight:650; }.r-statistic__prefix,.r-statistic__suffix { margin-inline:.15rem; font-size:.65em; }.r-steps { display:flex; gap:1rem; margin:0; padding:0; list-style:none; }.r-step { display:flex; flex:1; gap:.65rem; color:var(--r-muted); }.r-step--process { color:var(--r-primary); }.r-step--finish { color:#16a34a; }.r-step__marker { display:grid; width:1.6rem; height:1.6rem; flex:none; place-items:center; border:1px solid currentColor; border-radius:50%; }.r-step__title { color:var(--r-text); }.r-step__description { margin:.25rem 0 0; font-size:.85rem; }.r-result { display:flex; flex-direction:column; align-items:center; padding:2rem; text-align:center; }.r-result__icon { display:grid; width:3.5rem; height:3.5rem; place-items:center; border-radius:50%; background:#dcfce7; color:#15803d; font-size:1.8rem; }.r-result__title { margin:1rem 0 .3rem; }.r-result__subtitle { margin:0; color:var(--r-muted); }.r-result__extra { margin-top:1rem; }.r-collapse { border-top:1px solid var(--r-border); }.r-collapse-item { border-bottom:1px solid var(--r-border); }.r-collapse-item__title { padding:.8rem .2rem; color:var(--r-text); cursor:pointer; }.r-collapse-item__content { padding:0 .2rem .9rem; color:var(--r-muted); }.r-spinner { display:inline-block; width:1rem; height:1rem; border:2px solid currentColor; border-right-color:transparent; border-radius:50%; animation:r-spin .7s linear infinite; }@keyframes r-spin { to { transform:rotate(360deg); } }
.r-loading-host { position:relative !important; }.r-loading-overlay { position:absolute; z-index:20; inset:0; display:grid; place-items:center; background:color-mix(in srgb,var(--r-surface) 76%,transparent); color:var(--r-primary); }
@media (max-width:700px) { .r-descriptions__grid { grid-template-columns:1fr; }.r-steps { flex-direction:column; }.r-dialog { width:calc(100vw - 2rem) !important; } }
`

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
    if (typeof document !== 'undefined' && !document.getElementById('r-ui-styles')) {
      const style = document.createElement('style')
      style.id = 'r-ui-styles'
      style.textContent = styles
      document.head.appendChild(style)
    }
    for (const [name, component] of Object.entries(componentMap)) app.component(name, component)
    app.directive('loading', loadingDirective)
  },
}
