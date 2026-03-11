# Design System — PROJECT_NAME

## Brand Tokens
- Primary colour: #XXXXXX
- Secondary colour: #XXXXXX
- Surface / background: #XXXXXX
- Text primary: #XXXXXX
- Text secondary: #XXXXXX
- Border radius: Xpx (cards), Xpx (inputs), Xpx (pills)
- Spacing base unit: 4px — all spacing must be multiples of 4
- Shadow: define elevation levels here

## Typography
- Headings: [font] [weight]
- Body: [font] [weight], [size]/[line-height]
- Monospace: [font] (code blocks only)
- Type scale: define h1–h4 sizes here

## Component Rules
- Buttons: always use <Button> component, never raw <button>
- Forms: always use <FormField> wrapper
- Lists: never use bare <ul>, always <DataList> or <MenuList>
- Icons: [icon library name] only, no mixing libraries
- Add new component rules here as the system grows

## What Builders Must Never Do
- Inline styles (except truly dynamic values)
- Custom colours outside the token system
- New components without Design Guardian approval
- Mixing icon libraries
- Hardcoded spacing values (use spacing scale)

## Approved Patterns
List recurring UI patterns here: card layout, form layout, navigation structure, modal behaviour, etc.

## Change Log
Date | Change | Approved by
