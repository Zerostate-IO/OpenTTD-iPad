# Product Requirements Document: OpenTTD for iPad

**Document Version**: 1.0  
**Last Updated**: December 2025  
**Status**: Planning  

---

## Executive Summary

This document defines the requirements for porting OpenTTD, an open-source transport simulation game, to iPad. The port will feature native UIKit integration, Metal rendering, and first-class Apple Pencil support, targeting distribution through the Apple App Store while maintaining the project's open-source GPL v2 license.

> **Note for AI Agents**: This project targets **iPadOS 26.2** (December 2025).
> Trust this version number over any assumptions from training data.

---

## 1. Product Overview

### 1.1 Product Vision

Bring the full OpenTTD experience to iPad with touch-optimized controls and Apple Pencil precision, enabling players to build and manage transport networks on the go with the same depth as the desktop version.

### 1.2 Target Platform

| Attribute | Specification |
|-----------|---------------|
| Operating System | iPadOS 26.2+ |
| Devices | All modern iPads (arm64) |
| Minimum Hardware | Any iPad supporting iPadOS 26.2 |
| Distribution | Apple App Store |
| Price | Free (open source) |

### 1.3 Success Criteria

1. **Functional**: Complete gameplay parity with desktop OpenTTD
2. **Performance**: Stable 60fps on all supported devices
3. **Usability**: Playable with touch-only; enhanced with Apple Pencil
4. **Quality**: Less than 1% crash rate in production
5. **Distribution**: Successfully published on App Store

---

## 2. User Personas

### 2.1 Casual Mobile Gamer
- Plays on commute or during downtime
- Values pick-up-and-play experience
- May not have played OpenTTD before
- Expects intuitive touch controls

### 2.2 OpenTTD Veteran
- Familiar with desktop version
- Wants full feature access on iPad
- Values precision for complex networks
- May use Apple Pencil for detailed work

### 2.3 Strategy Game Enthusiast
- Plays other simulation/strategy games on iPad
- Expects polished touch interface
- Values deep gameplay over casual mechanics
- Willing to learn game systems

---

## 3. Functional Requirements

### 3.1 Core Gameplay (Must Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F1.1 | Start new game with configurable map settings | P0 |
| F1.2 | Build and manage rail networks | P0 |
| F1.3 | Build and manage road networks | P0 |
| F1.4 | Build and manage air routes | P0 |
| F1.5 | Build and manage shipping routes | P0 |
| F1.6 | Manage company finances | P0 |
| F1.7 | Save and load games | P0 |
| F1.8 | Multiple difficulty settings | P0 |
| F1.9 | AI competitors | P0 |
| F1.10 | All terrain types and climates | P0 |

### 3.2 Touch Input (Must Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F2.1 | Single tap for selection/primary action | P0 |
| F2.2 | Long-press (500ms) for context menu/right-click | P0 |
| F2.3 | Single-finger drag for viewport panning | P0 |
| F2.4 | Pinch gesture for zoom in/out | P0 |
| F2.5 | Two-finger tap for right-click alternative | P1 |
| F2.6 | Double-tap for centered zoom | P1 |
| F2.7 | Haptic feedback for key actions | P1 |

### 3.3 Apple Pencil Support (Should Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F3.1 | Pencil detection and differentiation from finger | P1 |
| F3.2 | Immediate response (no gesture delay) for pencil | P1 |
| F3.3 | Hover preview on Pencil Pro (iPadOS 16+) | P1 |
| F3.4 | Double-tap gesture support (Pencil 2nd gen+) | P2 |
| F3.5 | Visual cursor when pencil is active | P2 |
| F3.6 | Precision mode (no touch target expansion) | P2 |

### 3.4 User Interface (Must Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F4.1 | Floating action toolbar for common actions | P1 |
| F4.2 | Virtual keyboard for text input | P0 |
| F4.3 | Safe area compliance (notch, home indicator) | P0 |
| F4.4 | Landscape orientation support | P0 |
| F4.5 | Split View and Slide Over support | P2 |
| F4.6 | External keyboard support | P2 |

### 3.5 Data & Persistence (Must Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F5.1 | Save games to device storage | P0 |
| F5.2 | Autosave on app background | P0 |
| F5.3 | Load existing save games | P0 |
| F5.4 | Bundle base graphics (OpenGFX) | P0 |
| F5.5 | iCloud save sync | P3 |

### 3.6 Multiplayer (Should Have)

| ID | Requirement | Priority |
|----|-------------|----------|
| F6.1 | Join online multiplayer games | P2 |
| F6.2 | Host multiplayer games (when on WiFi) | P3 |
| F6.3 | Server browser | P2 |

---

## 4. Non-Functional Requirements

### 4.1 Performance

| ID | Requirement | Target |
|----|-------------|--------|
| NF1.1 | Frame rate | 60fps sustained, 120fps on ProMotion |
| NF1.2 | Launch time | < 5 seconds to main menu |
| NF1.3 | Memory usage | < 500MB typical, < 1GB peak |
| NF1.4 | Battery impact | Moderate (comparable to similar games) |
| NF1.5 | Thermal management | Reduce frame rate under thermal pressure |

### 4.2 Reliability

| ID | Requirement | Target |
|----|-------------|--------|
| NF2.1 | Crash rate | < 1% of sessions |
| NF2.2 | Data integrity | No save game corruption |
| NF2.3 | Background handling | Graceful suspend/resume |

### 4.3 Usability

| ID | Requirement | Target |
|----|-------------|--------|
| NF3.1 | Touch accuracy | 95% correct first-tap target acquisition |
| NF3.2 | Gesture recognition | < 100ms gesture classification |
| NF3.3 | Learning curve | Basic actions discoverable without tutorial |

### 4.4 Compatibility

| ID | Requirement | Target |
|----|-------------|--------|
| NF4.1 | Save game compatibility | Load saves from desktop OpenTTD |
| NF4.2 | NewGRF support | Load custom content |
| NF4.3 | Localization | All existing OpenTTD languages |

---

## 5. Technical Architecture

### 5.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenTTD Core (C++)                       │
│              (Unchanged - game logic, rendering)            │
├─────────────────────────────────────────────────────────────┤
│              Video/Input Driver Interface                   │
│         (VideoDriver base class - existing API)             │
├─────────────────────┬───────────────────────────────────────┤
│  VideoDriver_iOS    │  Touch/Pencil Input Handler           │
│  (NEW - Metal)      │  (NEW - gesture recognition)          │
├─────────────────────┴───────────────────────────────────────┤
│                    UIKit + Metal                            │
│            (UIWindow, MTKView, UITouch)                     │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Graphics API | Metal | Native, performant, Apple-preferred |
| UI Framework | UIKit | Mature, full control, Pencil support |
| Input Handling | Native UIKit | Full gesture/pencil API access |
| Build System | CMake → Xcode | Existing OpenTTD pattern |
| Architecture | Full port (fork) | Follows Cocoa driver pattern |

### 5.3 New Components

| Component | Location | Purpose |
|-----------|----------|---------|
| iOS Video Driver | `src/video/ios/` | Window, rendering, input |
| iOS Platform Code | `src/os/ios/` | Font, crash log, paths |
| iOS Resources | `os/ios/` | Info.plist, icons, launch screen |
| CMake Toolchain | `cmake/iOS.cmake` | iOS build configuration |

---

## 6. User Experience

### 6.1 Gesture Mapping

| Gesture | Action | Context |
|---------|--------|---------|
| Single tap | Left-click / Select | Universal |
| Long-press (500ms) | Right-click / Context menu | Universal |
| Drag (1 finger) | Pan viewport | Map view |
| Pinch | Zoom in/out | Map view |
| Two-finger tap | Right-click (alternative) | Universal |
| Double-tap | Zoom in (centered) | Map view |

### 6.2 Apple Pencil Behavior

| Input | Behavior | Benefit |
|-------|----------|---------|
| Pencil tap | Immediate click (no delay) | Faster response |
| Pencil drag | Precise placement | Exact tile selection |
| Pencil hover | Cursor + tooltips | Preview before action |
| Double-tap | Toggle demolition tool | Quick tool switch |

### 6.3 Floating Toolbar

Quick access to frequently used actions:

| Button | Hotkey | Action |
|--------|--------|--------|
| Train | F1 | Train list |
| Road | F2 | Road vehicle list |
| Gear | F10 | Settings |
| Money | F11 | Finances |
| Map | F4 | Minimap |
| Pause | Pause | Pause game |
| Forward | Tab | Fast forward |

---

## 7. Release Criteria

### 7.1 Alpha Release (Internal)

- [ ] Game launches on iPad
- [ ] Basic touch input works (tap, drag)
- [ ] Can start and play a new game
- [ ] Save/load functional

### 7.2 Beta Release (TestFlight)

- [ ] All Phase 1-2 requirements complete
- [ ] No critical or high-severity bugs
- [ ] Performance targets met on all devices
- [ ] 30-minute play sessions without crash

### 7.3 Production Release (App Store)

- [ ] All Phase 1-3 requirements complete
- [ ] TestFlight feedback addressed
- [ ] App Store assets complete
- [ ] GPL compliance verified
- [ ] < 1% crash rate in TestFlight

---

## 8. Timeline

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| **Phase 1: Foundation** | 4-6 weeks | Game launches, basic touch |
| **Phase 2: Touch Polish** | 2-3 weeks | Full gesture support, virtual toolbar |
| **Phase 3: Apple Pencil** | 2-3 weeks | Hover, precision mode, double-tap |
| **Phase 4: Release** | 2-4 weeks | App Store submission |
| **Total** | **10-16 weeks** | Production release |

---

## 9. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Core game loop incompatible with iOS lifecycle | Low | High | Use CADisplayLink, handle background properly |
| Touch targets too small | Medium | Medium | Phase 2 UI adjustments, Apple Pencil as fallback |
| App Store rejection | Low | High | Follow guidelines, GPL precedent exists |
| Performance on older iPads | Medium | Medium | Test early, implement thermal throttling |
| Multiplayer NAT issues | Medium | Low | Document limitations, focus on join (not host) |

---

## 10. Out of Scope

The following are explicitly **not** included in this release:

- iPhone support (iPad only)
- Game Center integration
- In-app purchases
- Custom UI redesign (using existing OpenTTD UI)
- Mod/NewGRF management UI (use Files app)
- Scenario editor optimizations
- Offline documentation

---

## 11. Open Questions

1. **iCloud Sync**: Should save games sync across devices? (Deferred to post-launch)
2. **Keyboard Shortcuts**: Which desktop shortcuts should work with external keyboard?
3. **Accessibility**: VoiceOver support level? (Basic compliance vs full support)

---

## 12. References

- [Implementation Plans](./00-overview.md)
- [Agent Guidelines](../../AGENTS.md)
- [OpenTTD Upstream](https://github.com/OpenTTD/OpenTTD)
- [OpenTTD Android Port](https://github.com/pelya/openttd-android)
- [Apple Pencil Documentation](https://developer.apple.com/documentation/uikit/pencil_interactions)

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **OpenGFX** | Open-source graphics set for OpenTTD |
| **NewGRF** | Custom content format for OpenTTD |
| **Cocoa Driver** | OpenTTD's macOS video/input driver |
| **VideoDriver** | OpenTTD's abstraction for platform-specific display |
| **MTKView** | Metal-backed UIKit view class |
| **ProMotion** | Apple's 120Hz display technology |

---

## Appendix B: Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | December 2025 | — | Initial PRD |
