# Movie-Buff

📖 Overview

Movie Buff is a modern iOS application built with SwiftUI that helps movie lovers discover, organize, and share movies and TV shows with friends.

Users can browse an extensive movie database, view detailed information about each title, discover where it's currently streaming, save favorites, share curated watchlists, and even participate in collaborative Watch Parties to decide what to watch together.

The app also features a Reels experience where users can discover new content by swiping through movie trailers and interacting with community comments and reviews.

✨ Features

🎥 Browse Movies & TV Shows
Browse an extensive movie and television database
View detailed information for every title
Access movie posters, ratings, genres, runtime, release dates, and descriptions
📺 Streaming Availability
View available streaming services for each movie or show
Tap a streaming platform to launch it directly
Quickly discover where content is available without searching multiple services
❤️ Favorites & Saved Lists
Save favorite movies and shows
Build your personal watchlist
Organize movies you want to watch later
Access your saved titles anytime
👥 Share With Friends
Share your saved lists with friends
Compare recommendations
Discover new movies through your social circle
🎲 Watch Party

Movie Buff includes a collaborative Watch Party mode.

Friends can:

Join a shared watch session
Shuffle through movie selections together
Swipe through recommendations
Decide on a movie as a group

Perfect for movie nights when no one can decide what to watch.

🎬 Movie Reels

Discover movies through an engaging short-form video experience.

Features include:

Swipe through movie trailers
Discover new releases
Browse trending content
Explore recommendations
💬 Trailer Discussions

Each trailer includes its own discussion thread.

Users can:

Post comments
Leave reviews
Read reactions from other users
Filter comments between:
🌍 Public
👥 Friends Only
🛠 Technology Stack
Technology	Purpose
SwiftUI	Native iOS User Interface
Swift	Application Logic
SQLite	Local Database Storage
Xcode	Development Environment
Vapor	Backend Server
🚀 Getting Started
Prerequisites
macOS
Xcode
Swift
SQLite
Vapor
Clone the Repository
git clone https://github.com/<your-username>/movie-buff.git

cd movie-buff
Start the Backend Server

From the server directory run:

swift App run serve

The Vapor server will start locally and serve the application's backend APIs.

Launch the iOS App
Open the project in Xcode.
Select an iOS Simulator or physical device.
Press Run (⌘ + R).
📱 Core Functionality
Browse Movies
Browse TV Shows
Movie Details
Streaming Availability
Favorite Movies
Saved Lists
Share Lists
Watch Party
Movie Trailer Reels
Trailer Comments
Friends-Only Comments
Public Reviews
📂 Project Structure
MovieBuff/
│
├── App/
├── Models/
├── Views/
├── ViewModels/
├── Services/
├── Components/
├── Resources/
├── Database/
├── Assets.xcassets/
└── Server/
🔮 Planned Features
AI-powered movie recommendations
Personalized watch suggestions
Push notifications
User profiles
Achievement badges
Movie trivia
Custom collections
Group voting
Advanced search filters
Offline saved lists
Apple TV integration
iPad optimization
🤝 Contributing

Contributions are welcome!

If you'd like to contribute:

Fork the repository.
Create a feature branch.
Commit your changes.
Push to your fork.
Open a Pull Request.
📄 License

This project is licensed under the MIT License.

👨‍💻 Developer

Built with ❤️ using SwiftUI, SQLite, and Vapor.

Movie Buff is designed to make discovering, sharing, and enjoying movies with friends simple, social, and fun.
