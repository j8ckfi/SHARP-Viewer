# Liquid Glass — SwiftUI Agent Reference

> **For AI coding assistants building iOS 26+ apps with Apple's Liquid Glass design language.**  
> Last updated: December 2025 | iOS 26.1+, Xcode 26+

---

## Quick Context

Liquid Glass is Apple's most significant UI overhaul since iOS 7, introduced at WWDC 2025. It's a translucent "meta-material" that reflects, refracts, and dynamically morphs. Ships across iOS 26, iPadOS 26, macOS Tahoe, watchOS 26, tvOS 26, and visionOS 26.

**Core principle:** Glass is exclusively for the **navigation layer** that floats above content. Never apply to content itself.

---

## Core APIs

### Primary Modifier

```swift
.glassEffect(_ glass: Glass = .regular, in shape: some Shape = .capsule, isEnabled: Bool = true)
```

### Glass Variants

| Variant | Use Case | Transparency |
|---------|----------|--------------|
| `.regular` | Default for most UI | Medium, fully adaptive |
| `.clear` | Media-rich backgrounds only | High, requires dimming layer |
| `.identity` | Conditional disable (no effect) | N/A |

### Interactive vs Standard Glass

```swift
// Standard glass — visual material only, scales on press
.glassEffect(.regular)

// Interactive glass — elastic physics, stretchable, bounces, shimmers
.glassEffect(.regular.interactive())
```

**When to use each:**

| Type | Behavior | Use For |
|------|----------|---------|
| `.interactive()` | Gel-like fluidity, touch-point illumination spreads to nearby glass, responds to drag | Primary floating actions, main navigation, prominent controls |
| Standard (no `.interactive()`) | Just scales on press | Secondary controls, utility buttons, less frequent actions |

> ⚠️ `.interactive()` is **iOS only** — no-op on macOS/tvOS.

### Tinting

```swift
.glassEffect(.regular.tint(.blue))
.glassEffect(.regular.tint(.purple.opacity(0.6)))
```

Use tinting to convey semantic meaning (primary action, state) — **not for decoration**.

---

## GlassEffectContainer

**Always wrap multiple glass elements in a container.** This is critical for:
- Shared rendering (reduces `CABackdropLayer` count → better performance)
- Morphing animations between elements
- Consistent sampling region

```swift
GlassEffectContainer {
    HStack(spacing: 20) {
        Button("Edit", systemImage: "pencil") { }
            .glassEffect(.regular.interactive())
        
        Button("Delete", systemImage: "trash") { }
            .glassEffect(.regular.interactive())
    }
}

// With spacing control (elements within this distance morph together)
GlassEffectContainer(spacing: 40) {
    // content
}
```

---

## Morphing Transitions

Requires:
1. Elements in same `GlassEffectContainer`
2. Each view has `glassEffectID` with shared namespace
3. Animation applied to state changes

```swift
struct MorphingExample: View {
    @State private var isExpanded = false
    @Namespace private var namespace
    
    var body: some View {
        GlassEffectContainer(spacing: 30) {
            Button(isExpanded ? "Collapse" : "Expand") {
                withAnimation(.bouncy) {
                    isExpanded.toggle()
                }
            }
            .glassEffect(.regular.interactive())
            .glassEffectID("toggle", in: namespace)
            
            if isExpanded {
                Button("Action") { }
                    .glassEffect(.regular.interactive())
                    .glassEffectID("action", in: namespace)
            }
        }
    }
}
```

### Union for Distant Elements

```swift
// Manually combine glass effects that are too far apart to auto-morph
.glassEffectUnion(id: "tools", namespace: controls)
```

---

## Button Styles

```swift
// Translucent, see-through — secondary actions
Button("Cancel") { }
    .buttonStyle(.glass)

// Opaque, prominent — primary actions
Button("Save") { }
    .buttonStyle(.glassProminent)
    .tint(.blue)
```

### Control Sizes

```swift
.controlSize(.mini)
.controlSize(.small)
.controlSize(.regular)      // Default
.controlSize(.large)
.controlSize(.extraLarge)   // New in iOS 26
```

### Border Shapes

```swift
.buttonBorderShape(.capsule)    // Default
.buttonBorderShape(.circle)
.buttonBorderShape(.roundedRectangle(radius: 8))
```

---

## Shapes

```swift
// Capsule (default)
.glassEffect(.regular, in: .capsule)

// Circle
.glassEffect(.regular, in: .circle)

// Rounded Rectangle
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

// Container-concentric (aligns with device/window corners)
.glassEffect(.regular, in: .rect(cornerRadius: .containerConcentric))
```

---

## Navigation Components

### TabView

```swift
TabView {
    Tab("Home", systemImage: "house") {
        HomeView()
    }
    
    // Search tab role — floating button at bottom-right
    Tab("Search", systemImage: "magnifyingglass", role: .search) {
        SearchView()
    }
}
.tabBarMinimizeBehavior(.onScrollDown)  // Collapses during scroll
.tabViewBottomAccessory {
    NowPlayingBar()
}
```

### Toolbars

Toolbars automatically get Liquid Glass. Don't add custom backgrounds.

```swift
.toolbar {
    ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Draw", systemImage: "pencil") { }
        Button("Erase", systemImage: "eraser") { }
    }
    
    ToolbarSpacer(.fixed, spacing: 20)
    
    ToolbarItem(placement: .topBarTrailing) {
        Button("Save", systemImage: "checkmark") { }
            .buttonStyle(.glassProminent)
    }
}
```

---

## ✅ DO

- **Use glass only for navigation layer** (toolbars, tab bars, floating controls, sheets)
- **Always use `GlassEffectContainer`** for multiple glass elements
- **Use `.interactive()`** for primary tappable elements on iOS
- **Let system handle accessibility** — it auto-adapts for Reduced Transparency, Increased Contrast, Reduced Motion
- **Use capsule shapes by default** — aligns with device corner concentricity
- **Prefer SF Symbol "none" variants** instead of `.circle` variants when inside glass
- **Use `.contentShape()`** to fix hit testing on custom glass buttons
- **Test on older devices** (iPhone 11-13 show lag)

---

## ❌ DON'T

- **Never apply glass to content** (lists, tables, images, media, scroll views)
- **Don't stack glass on glass** — breaks visual hierarchy
- **Avoid these modifiers on glass views:**
  - `.blur()`
  - `.opacity()` 
  - `.background()` with solid colors
  - `.clipShape()` (use the `in:` parameter instead)
- **Don't place solid fills behind glass** (`Color.white`, `Color.black`)
- **Don't nest `GlassEffectContainer`** inside another
- **Don't add `.background` or glass to toolbars** — they have built-in glass
- **Don't override accessibility settings** — let system handle it
- **Don't use `.clear` variant unless:**
  1. Element sits over media-rich content
  2. Content won't be hurt by dimming layer
  3. Content above glass is bold and bright

---

## Known Issues & Workarounds

### Menu Morphing Animation Breaks (iOS 26.1)

**Problem:** Menu glass morphing glitches when using `glassEffect` directly.

**Solution:** Use custom ButtonStyle:

```swift
struct GlassMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

Menu {
    // menu content
} label: {
    Image(systemName: "ellipsis")
        .frame(width: 44, height: 44)
}
.buttonStyle(GlassMenuButtonStyle())
```

> ⚠️ As of iOS 26.1, **don't place Menu inside GlassEffectContainer** — breaks morphing.

### Rotation Animation Glitches

**Problem:** `rotationEffect()` causes glass shape to deform during animation.

**Solution:** Bridge to UIKit:

```swift
struct GlassUIViewRepresentable: UIViewRepresentable {
    let cornerRadius: CGFloat
    let tintColor: UIColor?
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let glassEffect = UIGlassEffect()
        let effectView = UIVisualEffectView(effect: glassEffect)
        effectView.cornerConfiguration = .capsule
        return effectView
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) { }
}
```

### `.glassProminent` + `.circle` Artifacts

**Workaround:**

```swift
Button("Action") { }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .clipShape(Circle())  // Fixes rendering artifacts
```

### Hit Testing Fails on Glass Buttons

**Problem:** Only the icon/text is tappable, not the full glass area.

**Solution:**

```swift
Button { } label: {
    Image(systemName: "ellipsis")
        .frame(width: 44, height: 44)
}
.glassEffect(.regular.interactive(), in: .circle)
.contentShape(Circle())  // Fixes hit testing
```

---

## Accessibility

Glass automatically adapts to:
- **Reduced Transparency** — increases frosting
- **Increased Contrast** — stark colors and borders
- **Reduced Motion** — tones down animations/elasticity
- **Tinted Mode** (iOS 26.1+) — user-controlled opacity increase

**Don't override unless absolutely necessary:**

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

.glassEffect(reduceTransparency ? .identity : .regular)
```

---

## Performance Notes

- Each glass effect needs **3 offscreen textures** — expensive
- `GlassEffectContainer` reduces `CABackdropLayer` count significantly
- ~13% battery drain reported vs ~1% on iOS 18 in some tests
- Test on iPhone 11-13 for performance baseline
- Avoid continuous animations on glass elements

---

## Temporary Opt-Out (expires iOS 27)

```xml
<!-- Info.plist -->
<key>UIDesignRequiresCompatibility</key>
<true/>
```

---

## Availability Check

```swift
if #available(iOS 26.0, *) {
    content.glassEffect(.regular.interactive())
} else {
    content.background(.ultraThinMaterial)
}
```

---

## Quick Reference

```swift
// Basic
.glassEffect()
.glassEffect(.regular.interactive())
.glassEffect(.regular.tint(.blue))
.glassEffect(.clear)

// Shapes
.glassEffect(.regular, in: .capsule)
.glassEffect(.regular, in: .circle)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

// Container
GlassEffectContainer { }
GlassEffectContainer(spacing: 40) { }

// Morphing
.glassEffectID("id", in: namespace)
.glassEffectUnion(id: "id", namespace: namespace)
.glassEffectTransition(.materialize)  // Alternative to matchedGeometry

// Buttons
.buttonStyle(.glass)
.buttonStyle(.glassProminent)

// Navigation
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory { }
.sharedBackgroundVisibility(.hidden)
ToolbarSpacer(.fixed, spacing: 20)
```

---

## Sources

- [WWDC25 Session 219: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [WWDC25 Session 356: Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [Apple Developer Documentation: Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)