# Implementation Plan: Lens for E-Learning MVP

## Overview

This implementation plan breaks down the Lens for E-Learning MVP into discrete, actionable tasks. The system consists of a Flutter mobile app and a Python FastAPI backend running on AWS Lambda. The implementation follows a layered approach: infrastructure setup, backend API development, mobile app development, and integration testing.

The plan prioritizes core functionality first (authentication, image upload, OCR, search) before adding enhancements (offline support, history, bookmarks). Each major component includes property-based tests to validate correctness properties from the design document.

## Tasks

- [x] 1. Set up project infrastructure and development environment
  - Create AWS account and configure free tier services (S3, DynamoDB, Lambda, Cognito, API Gateway)
  - Set up Python backend project with FastAPI, pytest, hypothesis
  - Set up Flutter mobile project with required dependencies
  - Configure CI/CD pipeline (GitHub Actions)
  - Create DynamoDB table with single-table design schema
  - Configure S3 bucket with lifecycle policies
  - Set up Cognito User Pool with email verification
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

- [x] 2. Implement authentication service (Backend)
  - [x] 2.1 Create authentication API endpoints
    - Implement POST /api/v1/auth/register endpoint with Cognito integration
    - Implement POST /api/v1/auth/login endpoint with JWT token generation
    - Implement POST /api/v1/auth/logout endpoint
    - Implement POST /api/v1/auth/refresh endpoint for token refresh
    - Implement POST /api/v1/auth/verify-email endpoint
    - Implement GET /api/v1/auth/me endpoint for user profile
    - Add Pydantic models for request/response validation
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 1.7_
  
  - [ ]* 2.2 Write property test for authentication token validity
    - **Property 2: Token Validity Period**
    - **Validates: Requirements 1.3**
  
  - [ ]* 2.3 Write property test for invalid credentials rejection
    - **Property 3: Invalid Credentials Rejection**
    - **Validates: Requirements 1.4**
  
  - [ ]* 2.4 Write property test for logout token clearing
    - **Property 5: Logout Clears All Tokens**
    - **Validates: Requirements 1.7**
  
  - [ ]* 2.5 Write unit tests for authentication edge cases
    - Test email verification flow
    - Test token expiration handling
    - Test OAuth integration (Google, Facebook)
    - _Requirements: 1.2, 1.5, 1.6_

- [x] 3. Implement image upload handler (Backend Lambda)
  - [x] 3.1 Create upload handler Lambda function
    - Implement POST /api/v1/scans endpoint
    - Add image format validation (JPEG, PNG, HEIC)
    - Add image size validation (max 2MB)
    - Generate unique scan_id using UUID
    - Upload image to S3 with presigned URL
    - Create DynamoDB scan metadata record
    - Return scan_id and status to client
    - _Requirements: 2.3, 2.4, 2.5, 2.7_
  
  - [ ]* 3.2 Write property test for upload identifier uniqueness
    - **Property 9: Upload Identifier Uniqueness**
    - **Validates: Requirements 2.5**
  
  - [ ]* 3.3 Write property test for upload confirmation round-trip
    - **Property 11: Upload Confirmation Round-Trip**
    - **Validates: Requirements 2.7**
  
  - [ ]* 3.4 Write unit tests for upload validation
    - Test invalid image formats
    - Test oversized images
    - Test S3 upload failures
    - _Requirements: 2.3, 2.4, 2.6_

- [x] 4. Implement OCR processor (Backend Lambda)
  - [x] 4.1 Create OCR processor Lambda function
    - Set up Tesseract OCR in Lambda layer
    - Implement image preprocessing (grayscale, contrast enhancement)
    - Run Tesseract OCR with confidence scores
    - Validate minimum 50 characters extracted
    - Store extracted text in DynamoDB
    - Update scan status to "ocr_complete"
    - Invoke NLP Lambda asynchronously
    - Handle OCR errors with descriptive messages
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  
  - [ ]* 4.2 Write property test for OCR response structure
    - **Property 13: OCR Response Structure**
    - **Validates: Requirements 3.3**
  
  - [ ]* 4.3 Write property test for OCR result persistence
    - **Property 14: OCR Result Persistence**
    - **Validates: Requirements 3.7**
  
  - [ ]* 4.4 Write unit tests for OCR edge cases
    - Test insufficient text (<50 characters)
    - Test image quality issues
    - Test various image formats
    - _Requirements: 3.4, 3.5, 3.6_

- [x] 5. Implement NLP processor (Backend Lambda)
  - [x] 5.1 Create NLP processor Lambda function
    - Set up spaCy with en_core_web_sm model in Lambda layer
    - Implement text summarization algorithm (150-200 words for long text)
    - Handle short text (<100 words) by returning original
    - Implement RAKE keyword extraction (5-15 key phrases)
    - Prioritize multi-word phrases over single words
    - Store summary and keywords in DynamoDB
    - Update scan status to "nlp_complete"
    - Invoke Search Lambda asynchronously
    - Implement fallback to original text on summarization failure
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 5.1, 5.2, 5.3, 5.4_
  
  - [ ]* 5.2 Write property test for long text summarization
    - **Property 17: Long Text Summarization**
    - **Validates: Requirements 4.3**
  
  - [ ]* 5.3 Write property test for short text idempotence
    - **Property 18: Short Text Idempotence**
    - **Validates: Requirements 4.4**
  
  - [ ]* 5.4 Write property test for summary persistence round-trip
    - **Property 19: Summary Persistence Round-Trip**
    - **Validates: Requirements 4.5**
  
  - [ ]* 5.5 Write property test for keyword count bounds
    - **Property 22: Keyword Count Bounds**
    - **Validates: Requirements 5.2**
  
  - [ ]* 5.6 Write property test for keyword persistence round-trip
    - **Property 24: Keyword Persistence Round-Trip**
    - **Validates: Requirements 5.4**
  
  - [ ]* 5.7 Write unit tests for NLP edge cases
    - Test summarization fallback
    - Test keyword extraction with technical terms
    - Test empty text handling
    - _Requirements: 4.6, 5.3, 5.5_

- [x] 6. Checkpoint - Ensure backend processing pipeline works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement search orchestrator (Backend Lambda)
  - [x] 7.1 Create search orchestrator Lambda function
    - Set up YouTube Data API v3 client
    - Set up Google Custom Search API or Bing Search API client
    - Implement search query construction from keywords
    - Implement parallel search execution (videos, articles, websites)
    - Parse and rank search results
    - Deduplicate results
    - Store results in DynamoDB (max 10 per category)
    - Update scan status to "complete"
    - Handle partial failures (return results from successful categories)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_
  
  - [ ]* 7.2 Write property test for three-category search results
    - **Property 27: Three-Category Search Results**
    - **Validates: Requirements 6.2**
  
  - [ ]* 7.3 Write property test for video result count bounds
    - **Property 28: Video Result Count Bounds**
    - **Validates: Requirements 6.3**
  
  - [ ]* 7.4 Write property test for article result count bounds
    - **Property 29: Article Result Count Bounds**
    - **Validates: Requirements 6.4**
  
  - [ ]* 7.5 Write property test for website result count bounds
    - **Property 30: Website Result Count Bounds**
    - **Validates: Requirements 6.5**
  
  - [ ]* 7.6 Write property test for search result metadata completeness
    - **Property 31: Search Result Metadata Completeness**
    - **Validates: Requirements 6.6**
  
  - [ ]* 7.7 Write property test for parallel search execution
    - **Property 62: Parallel Search Execution**
    - **Validates: Requirements 12.5**
  
  - [ ]* 7.8 Write unit tests for search edge cases
    - Test empty search results
    - Test external API failures
    - Test rate limiting
    - _Requirements: 6.7, 11.7_

- [ ] 8. Implement error handling and monitoring (Backend)
  - [ ] 8.1 Add structured error responses
    - Create ErrorResponse Pydantic model
    - Implement error codes for all failure scenarios
    - Add request_id to all responses for debugging
    - Implement rate limiting with 429 responses
    - _Requirements: 11.4, 11.5, 11.7_
  
  - [ ]* 8.2 Write property test for structured error responses
    - **Property 56: Structured Error Responses**
    - **Validates: Requirements 11.5**
  
  - [ ]* 8.3 Write property test for rate limit response format
    - **Property 57: Rate Limit Response Format**
    - **Validates: Requirements 11.7**
  
  - [ ] 8.4 Set up CloudWatch logging and metrics
    - Configure structured logging with context
    - Add CloudWatch metrics (processing time, error rate, etc.)
    - Set up CloudWatch alarms for error thresholds
    - Implement metrics logging for free tier monitoring
    - _Requirements: 10.7, 11.4_
  
  - [ ]* 8.5 Write property test for error logging with context
    - **Property 55: Error Logging with Context**
    - **Validates: Requirements 11.4**

- [x] 9. Implement cost optimization features (Backend)
  - [x] 9.1 Add image compression and caching
    - Implement S3 image compression on storage
    - Implement duplicate image detection using content hash
    - Add caching layer for duplicate scans
    - Configure S3 lifecycle policies
    - _Requirements: 10.1, 10.2_
  
  - [ ]* 9.2 Write property test for image compression on storage
    - **Property 48: Image Compression on Storage**
    - **Validates: Requirements 10.1**
  
  - [ ]* 9.3 Write property test for duplicate image caching
    - **Property 49: Duplicate Image Caching**
    - **Validates: Requirements 10.2**
  
  - [ ]* 9.4 Write property test for Lambda execution time limit
    - **Property 50: Lambda Execution Time Limit**
    - **Validates: Requirements 10.3**

- [x] 10. Checkpoint - Ensure backend is complete and tested
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Implement authentication module (Mobile App)
  - [x] 11.1 Create authentication service and UI
    - Implement IAuthService interface with Cognito SDK
    - Create AuthProvider for state management
    - Implement TokenManager with secure storage
    - Build registration screen with email/password
    - Build login screen with email/password
    - Add Google OAuth login button
    - Add Facebook OAuth login button
    - Build email verification screen
    - Implement automatic token refresh
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_
  
  - [ ]* 11.2 Write property test for account creation consistency
    - **Property 1: Account Creation Consistency**
    - **Validates: Requirements 1.1**
  
  - [ ]* 11.3 Write property test for token expiry triggers re-authentication
    - **Property 4: Token Expiry Triggers Re-authentication**
    - **Validates: Requirements 1.6**
  
  - [ ]* 11.4 Write unit tests for authentication flows
    - Test registration flow
    - Test login flow
    - Test logout flow
    - Test token refresh
    - _Requirements: 1.1, 1.3, 1.6, 1.7_

- [x] 12. Implement camera and image capture module (Mobile App)
  - [x] 12.1 Create camera service and UI
    - Implement ICameraService interface
    - Build camera screen with live preview
    - Add capture button and gallery picker
    - Implement client-side image compression (max 2MB)
    - Add image format validation (JPEG, PNG, HEIC)
    - Save captured images locally before upload
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  
  - [ ]* 12.2 Write property test for local save before upload
    - **Property 6: Local Save Before Upload**
    - **Validates: Requirements 2.2**
  
  - [ ]* 12.3 Write property test for format validation
    - **Property 7: Format Validation**
    - **Validates: Requirements 2.3**
  
  - [ ]* 12.4 Write property test for compression size limit
    - **Property 8: Compression Size Limit**
    - **Validates: Requirements 2.4**
  
  - [ ]* 12.5 Write property test for client-side image compression
    - **Property 63: Client-Side Image Compression**
    - **Validates: Requirements 12.6**
  
  - [ ]* 12.6 Write unit tests for camera edge cases
    - Test camera permissions
    - Test gallery permissions
    - Test invalid image formats
    - _Requirements: 2.1, 2.3_

- [ ] 13. Implement scan processing module (Mobile App)
  - [ ] 13.1 Create scan orchestrator and progress tracking
    - Implement IScanService interface
    - Build scan upload with retry logic (3 attempts, exponential backoff)
    - Implement progress tracking for upload percentage
    - Add polling for scan status updates
    - Display status messages for each pipeline stage (OCR, Summarization, Keywords, Search)
    - Update progress indicator as stages complete
    - Handle background processing when user navigates away
    - Display success message and navigate to results on completion
    - Display stage-specific error messages on failure
    - _Requirements: 2.6, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7_
  
  - [ ]* 13.2 Write property test for upload retry logic
    - **Property 10: Upload Retry Logic**
    - **Validates: Requirements 2.6**
  
  - [ ]* 13.3 Write property test for upload progress indication
    - **Property 42: Upload Progress Indication**
    - **Validates: Requirements 9.1**
  
  - [ ]* 13.4 Write property test for pipeline stage status messages
    - **Property 43: Pipeline Stage Status Messages**
    - **Validates: Requirements 9.2**
  
  - [ ]* 13.5 Write property test for progress monotonicity
    - **Property 44: Progress Monotonicity**
    - **Validates: Requirements 9.3**
  
  - [ ]* 13.6 Write property test for stage-specific error messages
    - **Property 46: Stage-Specific Error Messages**
    - **Validates: Requirements 9.5**
  
  - [ ]* 13.7 Write property test for background processing continuation
    - **Property 47: Background Processing Continuation**
    - **Validates: Requirements 9.7**
  
  - [ ]* 13.8 Write unit tests for scan processing edge cases
    - Test network failures during upload
    - Test timeout handling
    - Test extended processing time messages
    - _Requirements: 9.6, 11.1, 11.2_

- [ ] 14. Implement results display module (Mobile App)
  - [ ] 14.1 Create results UI with tabbed categories
    - Build results screen with Videos, Articles, Websites tabs
    - Display resource title, description, and URL for each result
    - Show original image thumbnail and summary
    - Implement resource tap to open in-app browser or external app
    - Add bookmark button for each resource
    - Add share button to export results
    - _Requirements: 7.1, 7.2, 7.3, 7.6, 7.7_
  
  - [ ]* 14.2 Write property test for result field display completeness
    - **Property 32: Result Field Display Completeness**
    - **Validates: Requirements 7.2**
  
  - [ ]* 14.3 Write property test for results display includes context
    - **Property 35: Results Display Includes Context**
    - **Validates: Requirements 7.6**
  
  - [ ]* 14.4 Write unit tests for results display
    - Test tab switching
    - Test resource opening
    - Test sharing functionality
    - _Requirements: 7.1, 7.3, 7.7_

- [ ] 15. Implement bookmark management (Mobile App and Backend)
  - [ ] 15.1 Create bookmark service and API endpoints
    - Implement POST /api/v1/scans/{scan_id}/bookmarks endpoint
    - Implement GET /api/v1/bookmarks endpoint
    - Implement DELETE /api/v1/bookmarks/{bookmark_id} endpoint
    - Create bookmark manager in mobile app
    - Build bookmarks screen to display saved resources
    - Store bookmarks in DynamoDB
    - _Requirements: 7.4, 7.5_
  
  - [ ]* 15.2 Write property test for bookmark functionality
    - **Property 33: Bookmark Functionality**
    - **Validates: Requirements 7.4**
  
  - [ ]* 15.3 Write property test for bookmark persistence round-trip
    - **Property 34: Bookmark Persistence Round-Trip**
    - **Validates: Requirements 7.5**
  
  - [ ]* 15.4 Write unit tests for bookmark edge cases
    - Test duplicate bookmarks
    - Test bookmark deletion
    - Test bookmark sync
    - _Requirements: 7.4, 7.5_

- [ ] 16. Checkpoint - Ensure core mobile app features work
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 17. Implement scan history and offline access (Mobile App)
  - [ ] 17.1 Create local database and caching
    - Set up SQLite database with schema (scans, scan_keywords, resources, bookmarks)
    - Implement local caching of scan results
    - Build history screen with reverse chronological order
    - Display scan date, thumbnail, and summary preview
    - Implement tap to view full results
    - Add search and date range filtering
    - Enable offline access to cached data
    - Implement scan deletion (local and remote)
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_
  
  - [ ]* 17.2 Write property test for history chronological ordering
    - **Property 36: History Chronological Ordering**
    - **Validates: Requirements 8.1**
  
  - [ ]* 17.3 Write property test for history item display completeness
    - **Property 37: History Item Display Completeness**
    - **Validates: Requirements 8.2**
  
  - [ ]* 17.4 Write property test for result caching round-trip
    - **Property 38: Result Caching Round-Trip**
    - **Validates: Requirements 8.4**
  
  - [ ]* 17.5 Write property test for offline access to cached data
    - **Property 39: Offline Access to Cached Data**
    - **Validates: Requirements 8.5**
  
  - [ ]* 17.6 Write property test for deletion consistency
    - **Property 40: Deletion Consistency**
    - **Validates: Requirements 8.6**
  
  - [ ]* 17.7 Write property test for history search and filtering
    - **Property 41: History Search and Filtering**
    - **Validates: Requirements 8.7**
  
  - [ ]* 17.8 Write property test for history load time
    - **Property 60: History Load Time**
    - **Validates: Requirements 12.3**
  
  - [ ]* 17.9 Write property test for history pagination
    - **Property 61: History Pagination**
    - **Validates: Requirements 12.4**
  
  - [ ]* 17.10 Write unit tests for offline functionality
    - Test offline mode detection
    - Test background sync
    - Test conflict resolution
    - _Requirements: 8.4, 8.5, 11.1_

- [ ] 18. Implement network error handling and retry logic (Mobile App)
  - [ ] 18.1 Add error handling and retry mechanisms
    - Implement offline detection and queueing
    - Add exponential backoff retry (3 attempts)
    - Display user-friendly error messages
    - Show offline indicator in UI
    - Implement background sync when connectivity restored
    - _Requirements: 11.1, 11.2, 11.3_
  
  - [ ]* 18.2 Write property test for offline operation queueing
    - **Property 52: Offline Operation Queueing**
    - **Validates: Requirements 11.1**
  
  - [ ]* 18.3 Write property test for API retry with exponential backoff
    - **Property 53: API Retry with Exponential Backoff**
    - **Validates: Requirements 11.2**
  
  - [ ]* 18.4 Write property test for retry exhaustion error display
    - **Property 54: Retry Exhaustion Error Display**
    - **Validates: Requirements 11.3**
  
  - [ ]* 18.5 Write unit tests for network error scenarios
    - Test various network error types
    - Test retry timing
    - Test error message display
    - _Requirements: 11.1, 11.2, 11.3_

- [ ] 19. Implement performance optimizations
  - [ ] 19.1 Optimize backend processing pipeline
    - Add parallel processing for multiple scans
    - Optimize Lambda cold start times
    - Implement caching for spaCy model loading
    - Add database query optimization
    - _Requirements: 12.1, 12.2_
  
  - [ ]* 19.2 Write property test for pipeline processing time
    - **Property 58: Pipeline Processing Time**
    - **Validates: Requirements 12.1**
  
  - [ ]* 19.3 Write property test for concurrent scan processing
    - **Property 59: Concurrent Scan Processing**
    - **Validates: Requirements 12.2**
  
  - [ ] 19.4 Optimize mobile app performance
    - Implement lazy loading for history
    - Add image caching
    - Optimize UI rendering
    - _Requirements: 12.3, 12.4, 12.6_

- [ ] 20. Checkpoint - Ensure all features are complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 21. Integration testing and end-to-end flows
  - [ ]* 21.1 Write integration tests for complete scan pipeline
    - Test Upload → OCR → Summarization → Keywords → Search → Results flow
    - Test authentication flow with protected resources
    - Test offline flow with caching and sync
    - Test error recovery scenarios
    - _Requirements: All_
  
  - [ ]* 21.2 Write integration tests for edge cases
    - Test poor image quality handling
    - Test external API failures
    - Test rate limiting
    - Test concurrent user scenarios
    - _Requirements: 3.6, 6.7, 11.7, 12.2_

- [ ] 22. Deploy to AWS and configure production environment
  - Deploy Lambda functions with proper IAM roles
  - Configure API Gateway with Cognito authorizer
  - Set up CloudWatch alarms and monitoring
  - Configure S3 bucket policies and CORS
  - Set up DynamoDB with proper indexes
  - Test production deployment with smoke tests
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7_

- [ ] 23. Final checkpoint - Production readiness
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP delivery
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties with minimum 100 iterations each
- Unit tests validate specific examples and edge cases
- Integration tests validate end-to-end flows
- Checkpoints ensure incremental validation and provide opportunities for user feedback
- The implementation prioritizes core functionality (scan pipeline) before enhancements (history, bookmarks)
- All property tests must include a comment tag: `# Feature: lens-elearning-mvp, Property N: [Property Title]`
