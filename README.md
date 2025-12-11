# QuickLens

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)

**QuickLens** is a fast, intuitive, browser-based PDF analysis tool designed to help you extract, navigate, and understand large PDF documents with ease.

It uses chunk-based processing and intelligent navigation to let you inspect documents page-by-page, view compatible sections, and interact with PDF content smoothly — even on large files.

🔗 **Access QuickLens here:** 👉 [https://luissilva5002.github.io/quicklens/](https://luissilva5002.github.io/quicklens/)

---

## 🚀 Features

* **Instant Processing:** Drag-and-drop PDF upload for immediate analysis.
* **Chunk-Based Navigation:** Efficiently browse through large documents using intelligent chunking.
* **Fast Rendering:** High-performance page preview and rendering engine.
* **Smart Mapping:** Visualizes compatibility and relationships between different document chunks.
* **Responsive UI:** Clean and modern interface built with Flutter, optimized for both Web and Desktop.
* **Privacy First:** Runs **fully client-side** in your browser — no backend server required.

---

## 🛠️ Tech Stack

* **Framework:** [Flutter](https://flutter.dev) (Web & Desktop)
* **Language:** Dart
* **Core:** PDF Rendering Libraries, Custom chunk-navigation algorithms
* **Architecture:** Client-side processing

---

## 📂 Project Structure

quicklens/
 ├── lib/
 │   ├── pdfViewer.dart        # Core PDF visualization logic
 │   ├── ExtractorService.dart # Logic for chunking and extracting text
 │   ├── ui/                   # User Interface widgets and pages
 │   └── main.dart             # Application entry point
 ├── web/                      # Web-specific configuration
 ├── assets/                   # Static assets (icons, models, fonts)
 └── README.md                 # Project documentation

## 🌐 Live Demo

You can try QuickLens directly in your browser without installing anything:

👉 **[Launch QuickLens](https://luissilva5002.github.io/quicklens/)**

---

## 📜 License

This project is open-source. Feel free to use, modify, and contribute.