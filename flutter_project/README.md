# Anonymous Social Flutter App

This is a feature-rich, anonymous social media application built with Flutter and Supabase. It allows users to post content, interact with posts, join categories, and maintain a user profile, with a focus on anonymity and community interaction.

---

## Features

- **Authentication**: Secure email/password login and user registration.
- **Anonymous Posting**: Users can choose to post content anonymously, hiding their display name.
- **Interactive Feed**: A central feed to view all posts, with real-time updates.
- **Post Interactions**:
  - **Likes**: Users can like and unlike posts, with counts updated instantly.
  - **Comments**: A dedicated screen to view and add comments to any post.
- **Category System**:
  - Posts are organized into categories.
  - Users can filter the main feed to view posts from a specific category.
- **User Profiles**:
  - Users can set a display name, username, and avatar URL.
  - Users can join multiple categories of interest.
  - A dedicated screen allows users to edit their profile details at any time.
- **Post Management**:
  - Users can edit the content of their own posts.
  - An options menu is visible only to the author of a post.
- **Real-time & UX**:
  - **Pull-to-Refresh**: The feed can be manually refreshed.
  - **Real-time Updates**: The feed and comment screens listen for database changes and update automatically.
  - **Instant Feedback**: UI updates instantly after actions like liking, commenting, or creating posts.

---

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Supabase (Authentication, Realtime Database, Edge Functions/RPC)
- **Database**: PostgreSQL

---

## Project Setup

To run this project locally, you need to set up your own Supabase backend and configure the application to connect to it.

### 1. Supabase Setup

- **Create a Supabase Project**: Go to [supabase.com](https://supabase.com), create a new project, and save your Project URL and `anon` key.
- **Database Schema**: 
  - Navigate to the **SQL Editor** in your Supabase dashboard.
  - Open the `db/db_schema_v6.sql` file from this project, copy its entire contents, and run it as a new query. This will create all the necessary tables (`users`, `posts`, `comments`, etc.).
- **Database Functions (RPC)**:
  - In the SQL Editor, open the `db/seed_and_triggers.sql` file.
  - Copy the entire contents and run it as a new query. This sets up the critical RPC functions required for likes and comments to work correctly (`toggle_post_like`, `add_post_comment`, etc.).

### 2. Flutter Environment Setup

- **Create a `.env` file**: In the root of the `flutter_project` directory, create a file named `.env`.
- **Add Supabase Credentials**: Add your Supabase URL and `anon` key to the `.env` file like this:
  ```
  SUPABASE_URL=YOUR_SUPABASE_URL
  SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
  ```

### 3. Run the Application

- **Get Dependencies**: Open your terminal in the `flutter_project` directory and run:
  ```sh
  flutter pub get
  ```
- **Run the App**: Connect a device or start an emulator and run:
  ```sh
  flutter run
  ```

---

## Application Workflow

The application uses a straightforward but robust architecture centered around RPC functions for database writes and `select` queries for reads.

### Authentication Flow
1.  The app always starts at the `LoginScreen`.
2.  The user enters their credentials and taps "Sign in".
3.  `signInWithEmail()` is called, which authenticates with Supabase Auth.
4.  On success, the app immediately navigates to `FeedScreen`, replacing the `LoginScreen` in the navigation stack. This ensures the user cannot press the back button to return to the login page.

### Data & Interaction Flow (Example: Liking a Post)

This flow demonstrates how the app ensures data consistency and provides instant user feedback.

1.  **Data Fetch**: `FeedScreen` calls `_getPosts()`, which queries the `posts` table along with related `users` and `post_likes` data.
2.  **UI Display**: The list of posts is displayed in a `ListView.builder`. The app checks if the current user's ID is in the `post_likes` for each post to determine if the heart icon should be filled.
3.  **User Action**: The user taps the like button on a post.
4.  **RPC Call**: The `_toggleLike()` function in Flutter is called. It makes a single Remote Procedure Call (RPC) to the `toggle_post_like` function in the Supabase database.
5.  **Database Logic**: The `toggle_post_like` function in PostgreSQL runs with elevated privileges (`SECURITY DEFINER`):
    - It finds the user's profile ID from their authentication ID.
    - It checks if a like already exists from this user for this post.
    - It either `INSERT`s or `DELETE`s a row in the `post_likes` table.
    - It then runs a `COUNT(*)` and `UPDATE`s the `like_count` on the `posts` table. This all happens in a single, atomic transaction.
6.  **UI Update**: Back in the Flutter app, the `_toggleLike` function immediately calls `_refresh()`. This triggers a `setState`, which causes the `FutureBuilder` for the posts to run its future again, fetching the new, updated data and rebuilding the UI with the correct like count and icon state.

This combination of RPC functions for commands and `select` queries for reads is a robust pattern that ensures data consistency and a responsive user experience.

---

## Code Structure Overview

- `lib/main.dart`: Initializes services and launches the app. The `MyApp` widget sets the global theme and defines `LoginScreen` as the initial route.

- `lib/models.dart`: Contains the plain Dart objects (`Post`, `Comment`) that provide a structured way to handle the data retrieved from the database.

- `lib/screens/`: Contains all the UI for the application.
  - `login_screen.dart`: The initial screen. Handles user sign-in via email/password.
  - `register_screen.dart`: A comprehensive form for new users to create an account with a profile (name, avatar, categories, etc.).
  - `feed_screen.dart`: The main hub of the app. It uses a `FutureBuilder` to safely load and display posts. It manages the category filter, post fetching, pull-to-refresh, and real-time updates.
  - `comments_screen.dart`: A focused view for a single post's comments. Handles adding new comments and liking existing ones, with real-time updates scoped to the current post.
  - `create_post_screen.dart`: A simple form for creating a new post with content, a category, and an anonymous option.
  - `edit_post_screen.dart`: A simple form for a user to edit the content of their own post.
  - `edit_profile_screen.dart`: A form where users can manage their display name, username, avatar, and category memberships.

- `db/`: Contains the SQL scripts for setting up the database.
  - `db_schema_v6.sql`: The complete blueprint for the database. Contains `CREATE TABLE` statements for all application data.
  - `seed_and_triggers.sql`: Contains the business logic of the database. This includes the crucial RPC functions (`toggle_post_like`, etc.) that ensure data integrity and handle complex operations in a single, reliable step.
