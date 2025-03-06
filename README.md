# Cariocapp2

A modern iOS application for playing and scoring the card game Carioca.

## Overview

Cariocapp2 is a SwiftUI-based iOS application that helps players manage their Carioca card games. The app allows users to:

- Create and manage players
- Start new games with 2-4 players
- Track scores for each round
- View game history and statistics
- Follow the rules of Carioca

## Features

- **Player Management**: Create, edit, and delete players
- **Game Tracking**: Track scores for each round of Carioca
- **Statistics**: View player statistics and game history
- **Rules Reference**: Built-in rules for Carioca
- **Data Persistence**: Core Data for reliable data storage
- **Backup & Restore**: Export and import game data
- **Modern UI**: SwiftUI interface with haptic feedback and accessibility support

## Architecture

The app follows the MVVM (Model-View-ViewModel) architecture with Coordinators for navigation flow:

### Key Components

- **Models**: Core Data entities for Game, Player, and Round
- **Views**: SwiftUI views for different screens and components
- **ViewModels**: Business logic and state management
- **Coordinators**: Navigation and flow control
- **Repositories**: Data access layer
- **Managers**: Specialized functionality (Resources, Security, etc.)
- **Helpers**: Utility functions and extensions

### Project Structure

```
Cariocapp2/
├── App/                  # App entry point
├── Assets.xcassets/      # Images and assets
├── Cariocapp2.xcdatamodeld/ # Core Data model
├── Coordinators/         # Navigation coordinators
├── DependencyInjection.swift # Dependency container
├── Helpers/              # Utility classes
│   ├── Analytics.swift
│   ├── BackupManager.swift
│   ├── Formatters.swift
│   ├── HapticManager.swift
│   ├── Logger.swift
│   ├── SecurityManager.swift
│   ├── StateManager.swift
│   └── ViewModifiers.swift
├── Managers/             # Business logic managers
│   └── ResourceManager.swift
├── Models/               # Data models
├── Navigation/           # Navigation system
├── Persistence.swift     # Core Data controller
├── Repositories/         # Data access layer
├── ViewModels/           # View models
└── Views/                # UI components
    ├── Components/       # Reusable UI components
    └── [Screen]View.swift # Screen-specific views
```

## Dependencies

- **SwiftUI**: UI framework
- **CoreData**: Data persistence
- **Combine**: Reactive programming

## Requirements

- iOS 16.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

1. Clone the repository
2. Open `Cariocapp2.xcodeproj` in Xcode
3. Build and run the project on your device or simulator

## Usage

### Creating a New Game

1. Tap "New Game" on the main menu
2. Select 2-4 players
3. Configure game options
4. Start the game

### Scoring a Round

1. Play a round of Carioca according to the rules
2. When the round is complete, enter scores for each player
3. The app will calculate totals and advance to the next round

### Viewing Statistics

1. Tap "Game History" on the main menu
2. View past games and player statistics

## Architecture Details

### Dependency Injection

The app uses a dependency container to manage and provide access to shared resources:

- `DependencyContainer`: Central manager for app dependencies
- Environment values for SwiftUI integration

### Navigation System

- `NavigationCoordinator`: Manages navigation paths and sheet presentations
- `AppDestination`: Enum for navigation destinations
- `AppSheet`: Enum for sheet presentations

### State Management

- `AppState`: Manages and persists application state
- `StateManager`: Handles state restoration and persistence

### Data Layer

- `PersistenceController`: Manages Core Data stack
- `GameRepository`: Access to game data
- `PlayerRepository`: Access to player data

### Security

- `SecurityManager`: Input validation and sanitization
- Secure data handling

### Resource Management

- `ResourceManager`: Monitors system resources
- Memory and disk space management

## Best Practices

The app follows Apple's recommended best practices:

- **SwiftUI**: Modern declarative UI
- **Concurrency**: Async/await for asynchronous operations
- **Accessibility**: Support for VoiceOver and Dynamic Type
- **Localization**: Ready for internationalization
- **Error Handling**: Comprehensive error handling and recovery
- **Memory Management**: Efficient resource usage

## License

Copyright © 2025 Federico Antunovic. All rights reserved. 