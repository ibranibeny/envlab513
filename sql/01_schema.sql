/* ===========================================================================
   LAB513 - 01_schema.sql
   Creates the FAQ knowledge base objects referenced by Exercises 1-6:
     - dbo.FAQ_Content     (faq_id, category, question, answer)
     - dbo.FAQ_Embeddings  (faq_id, question_embedding VECTOR(1536))
   Run against the lab database: faq-ai-assistant-db
   =========================================================================== */

IF OBJECT_ID('dbo.FAQ_Embeddings', 'U') IS NOT NULL
    DROP TABLE dbo.FAQ_Embeddings;
GO
IF OBJECT_ID('dbo.FAQ_Content', 'U') IS NOT NULL
    DROP TABLE dbo.FAQ_Content;
GO

CREATE TABLE dbo.FAQ_Content
(
    faq_id   INT            NOT NULL CONSTRAINT PK_FAQ_Content PRIMARY KEY,
    category NVARCHAR(100)  NOT NULL,
    question NVARCHAR(1000) NOT NULL,
    answer   NVARCHAR(MAX)  NOT NULL
);
GO

/* question_embedding holds the 1,536-dimension vector for each FAQ question.
   VECTOR is generally available in Azure SQL Database. */
CREATE TABLE dbo.FAQ_Embeddings
(
    faq_id             INT          NOT NULL
        CONSTRAINT PK_FAQ_Embeddings PRIMARY KEY
        CONSTRAINT FK_FAQ_Embeddings_Content
            REFERENCES dbo.FAQ_Content (faq_id),
    question_embedding VECTOR(1536) NULL
);
GO

PRINT 'Schema ready: dbo.FAQ_Content + dbo.FAQ_Embeddings';
GO
