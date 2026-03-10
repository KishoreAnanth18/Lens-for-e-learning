# Requirements Document: Lens for E-Learning MVP

## Introduction

Lens for E-Learning is a mobile application that enables students to scan textbook pages and automatically discover relevant learning resources. The system uses OCR to extract text from images, processes the content to identify key concepts, and searches for educational materials including videos, articles, and websites. This MVP targets 50-100 active users processing up to 10,000 scans per month while operating entirely within AWS free tier limits.

## Glossary

- **Mobile_App**: The Flutter-based cross-platform mobile application (iOS and Android)
- **Backend_API**: The FastAPI REST API service running on AWS Lambda
- **OCR_Service**: The Tesseract-based optical character recognition component
- **NLP_Service**: The spaCy-based natural language processing component for text summarization
- **Keyword_Extractor**: The RAKE algorithm-based component for extracting key phrases
- **Search_Service**: The component that queries external sources for learning resources
- **Storage_Service**: AWS S3 service for storing uploaded images
- **Database_Service**: AWS DynamoDB service for storing user data and scan history
- **Auth_Service**: AWS Cognito service for user authentication and authorization
- **Scan**: A single instance of processing a textbook image through the complete pipeline
- **Learning_Resource**: An external educational material (video, article, or website)
- **Scan_History**: The collection of all scans performed by a user
- **Processing_Pipeline**: The sequential execution of OCR → Summarization → Keyword Extraction → Search

## Requirements

### Requirement 1: User Authentication and Authorization

**User Story:** As a student, I want to securely register and login to the app, so that I can access my personal scan history and saved resources.

#### Acceptance Criteria

1. WHEN a new user registers, THE Auth_Service SHALL create a user account with email and password
2. WHEN a user registers, THE Auth_Service SHALL send a verification email to confirm the account
3. WHEN a user logs in with valid credentials, THE Auth_Service SHALL return an authentication token valid for 30 days
4. WHEN a user logs in with invalid credentials, THE Auth_Service SHALL reject the request and return an error message
5. WHERE social login is available, THE Auth_Service SHALL support Google and Facebook OAuth authentication
6. WHEN an authentication token expires, THE Mobile_App SHALL prompt the user to re-authenticate
7. WHEN a user logs out, THE Mobile_App SHALL clear all local authentication tokens

### Requirement 2: Image Capture and Upload

**User Story:** As a student, I want to capture or upload images of textbook pages, so that I can extract learning content from physical materials.

#### Acceptance Criteria

1. WHEN a user opens the camera interface, THE Mobile_App SHALL display a live camera preview with capture controls
2. WHEN a user captures an image, THE Mobile_App SHALL save the image locally before upload
3. WHEN a user selects gallery upload, THE Mobile_App SHALL allow selection of images in JPEG, PNG, or HEIC formats
4. WHEN an image is selected or captured, THE Mobile_App SHALL compress the image to maximum 2MB while maintaining readability
5. WHEN uploading an image, THE Mobile_App SHALL upload to the Storage_Service with a unique identifier
6. WHEN an upload fails, THE Mobile_App SHALL retry up to 3 times with exponential backoff
7. WHEN an upload completes, THE Mobile_App SHALL receive a confirmation with the image storage URL

### Requirement 3: OCR Text Extraction

**User Story:** As a student, I want the system to extract text from my textbook images, so that I can search for relevant learning resources.

#### Acceptance Criteria

1. WHEN an image is uploaded, THE Backend_API SHALL trigger the OCR_Service to process the image
2. WHEN processing an image, THE OCR_Service SHALL extract text using Tesseract OCR engine
3. WHEN text extraction completes, THE OCR_Service SHALL return the extracted text with confidence scores
4. IF the extracted text has less than 50 characters, THEN THE Backend_API SHALL return an error indicating insufficient content
5. WHEN OCR processing fails, THE Backend_API SHALL return a descriptive error message to the Mobile_App
6. WHEN processing clear textbook images, THE OCR_Service SHALL achieve minimum 95% character accuracy
7. WHEN OCR completes, THE Backend_API SHALL store the extracted text in the Database_Service

### Requirement 4: Text Summarization

**User Story:** As a student, I want the system to summarize extracted text, so that I can quickly understand the main concepts without reading everything.

#### Acceptance Criteria

1. WHEN OCR extraction completes, THE NLP_Service SHALL generate a summary of the extracted text
2. WHEN summarizing text, THE NLP_Service SHALL use spaCy with the en_core_web_sm model
3. WHEN the extracted text exceeds 500 words, THE NLP_Service SHALL reduce it to approximately 150-200 words
4. WHEN the extracted text is less than 100 words, THE NLP_Service SHALL return the original text as the summary
5. WHEN summarization completes, THE Backend_API SHALL store the summary in the Database_Service
6. WHEN summarization fails, THE Backend_API SHALL use the original extracted text as fallback

### Requirement 5: Keyword and Keyphrase Extraction

**User Story:** As a student, I want the system to identify key concepts from my textbook pages, so that I can find targeted learning resources.

#### Acceptance Criteria

1. WHEN text summarization completes, THE Keyword_Extractor SHALL extract key phrases using the RAKE algorithm
2. WHEN extracting keywords, THE Keyword_Extractor SHALL return between 5 and 15 key phrases ranked by relevance
3. WHEN the text contains technical terms, THE Keyword_Extractor SHALL prioritize multi-word phrases over single words
4. WHEN keyword extraction completes, THE Backend_API SHALL store the keywords in the Database_Service
5. WHEN keyword extraction fails, THE Backend_API SHALL return an error and halt the processing pipeline

### Requirement 6: Learning Resource Search

**User Story:** As a student, I want the system to automatically find relevant learning resources, so that I can explore materials related to my textbook content.

#### Acceptance Criteria

1. WHEN keyword extraction completes, THE Search_Service SHALL query external sources for learning resources
2. WHEN searching, THE Search_Service SHALL find resources in three categories: YouTube videos, articles, and websites
3. WHEN searching for videos, THE Search_Service SHALL return at least 3 and at most 10 relevant YouTube videos
4. WHEN searching for articles, THE Search_Service SHALL return at least 3 and at most 10 relevant educational articles
5. WHEN searching for websites, THE Search_Service SHALL return at least 3 and at most 10 relevant educational websites
6. WHEN search completes, THE Backend_API SHALL store all results in the Database_Service with metadata including title, URL, description, and category
7. IF no results are found for a category, THEN THE Search_Service SHALL return an empty list for that category without failing

### Requirement 7: Results Display and Management

**User Story:** As a student, I want to view my scan results organized by category, so that I can easily access different types of learning materials.

#### Acceptance Criteria

1. WHEN processing completes, THE Mobile_App SHALL display results organized into Videos, Articles, and Websites tabs
2. WHEN displaying a result, THE Mobile_App SHALL show the title, description, and source URL
3. WHEN a user taps a result, THE Mobile_App SHALL open the resource in an in-app browser or external app
4. WHEN viewing results, THE Mobile_App SHALL allow users to bookmark individual resources
5. WHEN a user bookmarks a resource, THE Mobile_App SHALL store the bookmark in the Database_Service
6. WHEN displaying results, THE Mobile_App SHALL show the original image thumbnail and extracted summary
7. WHEN results are displayed, THE Mobile_App SHALL provide a share button to export results via standard sharing mechanisms

### Requirement 8: Scan History and Offline Access

**User Story:** As a student, I want to access my previous scans and results, so that I can review materials without repeating the scanning process.

#### Acceptance Criteria

1. WHEN a user opens the history view, THE Mobile_App SHALL display all previous scans in reverse chronological order
2. WHEN displaying scan history, THE Mobile_App SHALL show the scan date, thumbnail image, and summary preview
3. WHEN a user taps a history item, THE Mobile_App SHALL display the full results for that scan
4. WHEN scan results are received, THE Mobile_App SHALL cache the results locally for offline access
5. WHILE offline, THE Mobile_App SHALL allow users to view cached scan history and results
6. WHEN a user deletes a scan from history, THE Mobile_App SHALL remove it from local cache and the Database_Service
7. WHEN viewing history, THE Mobile_App SHALL support search and filtering by date range

### Requirement 9: Processing Status and Feedback

**User Story:** As a student, I want to see real-time progress of my scan processing, so that I know the system is working and how long to wait.

#### Acceptance Criteria

1. WHEN an image upload starts, THE Mobile_App SHALL display a progress indicator showing upload percentage
2. WHEN processing begins, THE Mobile_App SHALL display status messages for each pipeline stage: OCR, Summarization, Keyword Extraction, and Search
3. WHEN each pipeline stage completes, THE Mobile_App SHALL update the progress indicator to reflect completion
4. WHEN processing completes successfully, THE Mobile_App SHALL display a success message and navigate to results
5. IF processing fails at any stage, THEN THE Mobile_App SHALL display a specific error message indicating which stage failed
6. WHEN processing takes longer than 30 seconds, THE Mobile_App SHALL display a message indicating extended processing time
7. WHEN the user navigates away during processing, THE Mobile_App SHALL continue processing in the background and notify when complete

### Requirement 10: Cost Optimization and Free Tier Compliance

**User Story:** As a project owner, I want the system to operate within AWS free tier limits, so that the MVP incurs zero hosting costs.

#### Acceptance Criteria

1. WHEN storing images, THE Storage_Service SHALL compress and optimize images to minimize S3 storage usage
2. WHEN processing scans, THE Backend_API SHALL implement caching to avoid redundant processing of identical images
3. WHEN a Lambda function executes, THE Backend_API SHALL complete processing within 15 minutes to avoid timeout charges
4. WHEN storing data, THE Database_Service SHALL use efficient data structures to stay within 25GB DynamoDB free tier
5. WHEN users authenticate, THE Auth_Service SHALL stay within 50,000 monthly active users limit
6. WHEN Lambda functions are invoked, THE Backend_API SHALL stay within 1 million requests per month free tier
7. WHEN monitoring usage, THE Backend_API SHALL log metrics to track free tier consumption

### Requirement 11: Error Handling and Resilience

**User Story:** As a student, I want the app to handle errors gracefully, so that I understand what went wrong and can take corrective action.

#### Acceptance Criteria

1. WHEN network connectivity is lost, THE Mobile_App SHALL display an offline message and queue operations for retry
2. WHEN an API request fails, THE Mobile_App SHALL retry with exponential backoff up to 3 attempts
3. IF all retry attempts fail, THEN THE Mobile_App SHALL display a user-friendly error message with suggested actions
4. WHEN the Backend_API encounters an error, THE Backend_API SHALL log the error with context for debugging
5. WHEN processing fails, THE Backend_API SHALL return structured error responses with error codes and messages
6. WHEN an image is unreadable, THE Backend_API SHALL return a specific error indicating poor image quality
7. WHEN rate limits are exceeded, THE Backend_API SHALL return a 429 status code with retry-after information

### Requirement 12: Performance and Scalability

**User Story:** As a student, I want my scans to process quickly, so that I can get learning resources without long waits.

#### Acceptance Criteria

1. WHEN processing a scan, THE Backend_API SHALL complete the entire pipeline within 30 seconds for 90% of requests
2. WHEN multiple scans are submitted, THE Backend_API SHALL process them concurrently using separate Lambda invocations
3. WHEN loading scan history, THE Mobile_App SHALL display the first 20 results within 2 seconds
4. WHEN scrolling through history, THE Mobile_App SHALL implement pagination to load additional results on demand
5. WHEN searching for resources, THE Search_Service SHALL implement parallel queries to minimize total search time
6. WHEN images are uploaded, THE Mobile_App SHALL compress images client-side to reduce upload time
7. WHEN the system reaches 10,000 scans per month, THE Backend_API SHALL maintain the same performance characteristics
