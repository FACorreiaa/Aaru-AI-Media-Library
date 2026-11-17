//  @ts-check

// ESLint runs only what oxlint cannot express: the JSX selectors of the web UI
// rule and two house-style rules oxlint has no version of. Everything else,
// including the type-aware rules and the barrel import rule, is oxlint: see
// .oxlintrc.json. Files are parsed without type information (no `project`), which
// was the slow part of the old lint. eslint-plugin-oxlint goes last and turns off
// any rule here that oxlint already reports.
import { tanstackConfig } from '@tanstack/eslint-config'
import oxlint from 'eslint-plugin-oxlint'

// The TypeScript parser and the plugins come from @tanstack/eslint-config; none
// of its rules are switched on from there.
const tanstack = tanstackConfig.find(
  (config) => config.name === 'tanstack/javascript',
)
if (!tanstack) throw new Error('@tanstack/eslint-config: no javascript config')

const SLOT_TWICE = {
  // A JSX slot read in a Show/Match `when` and again in its body is created twice; on a hard
  // load the first copy claims the server's nodes and Kobalte's Dynamic in the second finds
  // none ("template is not a function"). Resolve it once with `children(() => props.x)`.
  selector:
    "JSXAttribute[name.name='when'] > JSXExpressionContainer > MemberExpression[object.name='props'][property.name=/^(children|description|footer)$/]",
  message:
    'Resolve a JSX slot once with children(() => props.x) and test that: reading props.x in `when` and again in the body creates it twice and breaks hydration.',
}

// shadcn-solid's source as its registry ships it, so a later copy diffs cleanly against
// upstream.
const VENDORED = [
  'src/components/ui/**',
  'src/lib/cva.ts',
  'src/lib/call-handler.ts',
  'src/lib/combine-style.ts',
  'src/hooks/use-mobile.ts',
]

export default [
  {
    files: ['**/*.{js,mjs,ts,tsx}'],
    languageOptions: {
      sourceType: 'module',
      ecmaVersion: 'latest',
      parser: tanstack.languageOptions.parser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    plugins: {
      '@stylistic': tanstack.plugins['@stylistic'],
      '@typescript-eslint': tanstack.plugins['@typescript-eslint'],
    },
    rules: {
      '@stylistic/spaced-comment': tanstack.rules['@stylistic/spaced-comment'],
      '@typescript-eslint/naming-convention':
        tanstack.rules['@typescript-eslint/naming-convention'],
    },
  },
  {
    files: VENDORED,
    rules: { '@typescript-eslint/naming-convention': 'off' },
  },
  // The web UI rule (CLAUDE.md): every control comes from shadcn-solid in components/ui.
  // Raw form controls and modals go through the components (Button, TextField, Select,
  // Dialog…). Every caller is migrated (WEB-005), so a new raw one fails the lint. The other
  // half of the rule, importing through the barrel, is no-restricted-imports in
  // .oxlintrc.json.
  {
    files: ['src/**/*.{ts,tsx}'],
    ignores: ['src/components/ui/**'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector:
            'JSXOpeningElement[name.name=/^(button|input|select|textarea|dialog)$/]',
          message:
            'Use the shadcn-solid component from ~/components/ui instead of a raw element; add it from shadcn-solid if it is missing.',
        },
        SLOT_TWICE,
      ],
    },
  },
  // The same slot rule inside components/ui, where raw elements are allowed.
  {
    files: ['src/components/ui/**/*.tsx'],
    rules: { 'no-restricted-syntax': ['error', SLOT_TWICE] },
  },
  {
    ignores: [
      'eslint.config.js',
      'prettier.config.js',
      'worker-configuration.d.ts',
      'src/routeTree.gen.ts',
      'src/lib/api/schema.d.ts',
      // Plain browser JavaScript served as-is, outside the TypeScript project.
      'public/sw.js',
      '.output/**',
      'dist/**',
    ],
  },
  ...oxlint.buildFromOxlintConfigFile('./.oxlintrc.json'),
]
