//  @ts-check

import { tanstackConfig } from '@tanstack/eslint-config'

const SLOT_TWICE = {
  // A JSX slot read in a Show/Match `when` and again in its body is created twice; on a hard
  // load the first copy claims the server's nodes and Kobalte's Dynamic in the second finds
  // none ("template is not a function"). Resolve it once with `children(() => props.x)`.
  selector:
    "JSXAttribute[name.name='when'] > JSXExpressionContainer > MemberExpression[object.name='props'][property.name=/^(children|description|footer)$/]",
  message:
    'Resolve a JSX slot once with children(() => props.x) and test that: reading props.x in `when` and again in the body creates it twice and breaks hydration.',
}

export default [
  ...tanstackConfig,
  {
    rules: {
      'import/no-cycle': 'off',
      'import/order': 'off',
      'sort-imports': 'off',
      '@typescript-eslint/array-type': 'off',
      '@typescript-eslint/require-await': 'off',
      'pnpm/json-enforce-catalog': 'off',
    },
  },
  // shadcn-solid's source as its registry ships it, so a later copy diffs cleanly against
  // upstream. Only the house-style rules its code breaks are off here; the type assertions
  // TypeScript reports as unnecessary are what Kobalte's polymorphic props need.
  {
    files: [
      'src/components/ui/**',
      'src/lib/cva.ts',
      'src/lib/call-handler.ts',
      'src/lib/combine-style.ts',
      'src/hooks/use-mobile.ts',
    ],
    rules: {
      '@typescript-eslint/naming-convention': 'off',
      '@typescript-eslint/no-unnecessary-type-assertion': 'off',
      '@typescript-eslint/no-unsafe-function-type': 'off',
      'import/consistent-type-specifier-style': 'off',
      'import/no-duplicates': 'off',
      'no-shadow': 'off',
    },
  },
  // The web UI rule (CLAUDE.md): every control comes from shadcn-solid in components/ui,
  // imported through its barrel. Inside components/ui the components import each other freely.
  {
    files: ['src/**/*.{ts,tsx}'],
    ignores: ['src/components/ui/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              regex: '^~/components/ui/.+',
              message:
                "Import UI from the barrel, '~/components/ui', not from its files.",
            },
            {
              regex: '^\\.{1,2}/(.*/)?(components/)?ui(/.*)?$',
              message:
                "Import UI as '~/components/ui', not by a relative path.",
            },
          ],
        },
      ],
      // Raw form controls and modals go through the components (Button, TextField, Select,
      // Dialog…). Every caller is migrated (WEB-005), so a new raw one fails the lint.
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
]
