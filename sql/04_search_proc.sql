/* ===========================================================================
   LAB513 - 04_search_proc.sql   (TEMPLATE)
   Creates dbo.SearchFAQ - the semantic search stored procedure used by
   Exercises 1, 3 and 4.

   Contract (must not change - Exercise 3 depends on it):
     INPUT : @user_question NVARCHAR(1000)
     OUTPUT: a result set with exactly these 4 columns, in this order:
                 faq_id (INT), category, question, answer
             ordered by semantic similarity (closest first), TOP 3.

   Exercise 3 relies on the 4-column shape:
       INSERT INTO #searchResults (faq_id, category, question, answer)
       EXEC dbo.SearchFAQ @user_question = @user_question;

   Placeholders @@EMBED_URL@@ / @@AI_ACCOUNT_URL@@ are substituted by deploy.sh.
   Authentication uses the SQL server's MANAGED IDENTITY (token, no api-key) via
   the DATABASE SCOPED CREDENTIAL created in 03_generate_embeddings.sql.

   Note on VECTOR_DISTANCE: the metric ('cosine') is the FIRST argument,
   followed by the two vectors (Exercise 2 highlights this ordering).
   =========================================================================== */

CREATE OR ALTER PROCEDURE dbo.SearchFAQ
    @user_question NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @payload  NVARCHAR(MAX),
            @response NVARCHAR(MAX),
            @qvec     VECTOR(1536);

    -- 1) Embed the incoming question with Azure OpenAI.
    SET @payload = N'{"input":"' + STRING_ESCAPE(@user_question, 'json') + N'"}';

    EXEC sp_invoke_external_rest_endpoint
        @method     = 'POST',
        @url        = N'@@EMBED_URL@@',
        @credential = [@@AI_ACCOUNT_URL@@],
        @payload    = @payload,
        @response   = @response OUTPUT;

    SET @qvec = CAST(JSON_QUERY(@response, '$.result.data[0].embedding') AS VECTOR(1536));

    -- 2) Return the 3 closest FAQ rows by cosine distance.
    SELECT TOP (3)
        c.faq_id,
        c.category,
        c.question,
        c.answer
    FROM dbo.FAQ_Content   AS c
    JOIN dbo.FAQ_Embeddings AS e ON e.faq_id = c.faq_id
    WHERE e.question_embedding IS NOT NULL
    ORDER BY VECTOR_DISTANCE('cosine', @qvec, e.question_embedding) ASC;
END
GO

PRINT 'Stored procedure ready: dbo.SearchFAQ';
GO
