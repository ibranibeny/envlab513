/* ===========================================================================
   06_rag_chat.sql  -  Exercise 3 (RAG): send the grounded prompt to gpt-5.

   WORKSHOP NOTE — TOKEN vs API-KEY
   --------------------------------
   The official lab (exercise-03.md, Task 2) authenticates to Azure OpenAI with
   an API KEY:

        DECLARE @headers NVARCHAR(MAX) = N'{"api-key": "<YOUR-KEY>"}';
        EXEC sp_invoke_external_rest_endpoint
             @method='POST', @url=N'<chat-completions-url>',
             @headers=@headers, @payload=@payload, @response=@response OUTPUT;

   In THIS environment the AI account has local (key) auth DISABLED
   (`disableLocalAuth=true`), so the api-key path returns 401. We therefore call
   the model with a TOKEN (the SQL server's Managed Identity) via the
   `@credential` parameter + the DATABASE SCOPED CREDENTIAL created in
   03_generate_embeddings.sql. No key is ever stored in the query.

   Run this AFTER the SQL bootstrap (needs dbo.SearchFAQ, the DSC, the master
   key, and the "Cognitive Services OpenAI User" role on the SQL MI).

   The @url / @credential below are PRE-FILLED with concrete values for the
   current deployment (account aif-lab513-2139d8, model gpt-5). If you redeploy
   to a different AI account, replace both with your own account URL (the
   @credential name must equal the account URL WITHOUT a trailing slash and
   must exist as the Managed-Identity DATABASE SCOPED CREDENTIAL).
   =========================================================================== */

SET NOCOUNT ON;

/* ---------- Task 1: retrieval + build the grounded prompt ---------- */
DECLARE @user_question NVARCHAR(1000) = N'My product arrived damaged';
DECLARE @context NVARCHAR(MAX);
DECLARE @prompt  NVARCHAR(MAX);

CREATE TABLE #searchResults (
    faq_id   INT,
    category NVARCHAR(200),
    question NVARCHAR(MAX),
    answer   NVARCHAR(MAX)
);

INSERT INTO #searchResults (faq_id, category, question, answer)
EXEC dbo.SearchFAQ @user_question = @user_question;

SELECT @context =
(
    SELECT STRING_AGG(
        CONCAT(N'Question: ', question, CHAR(10), N'Answer: ', answer),
        CHAR(10) + CHAR(10)
    )
    FROM #searchResults
);

SET @prompt =
    N'Use ONLY the context below to answer the question.' + CHAR(10) +
    N'Context:' + CHAR(10) + ISNULL(@context, N'No relevant FAQ context found.') + CHAR(10) +
    N'Question:' + CHAR(10) + @user_question + CHAR(10) +
    N'If the answer is not in the context, say you do not know.';

DROP TABLE #searchResults;

/* ---------- Task 2: send the prompt to gpt-5 using a TOKEN (Managed Identity) ---------- */
-- NOTE: gpt-5 is a reasoning model and only supports the default temperature (1);
-- sending "temperature":0 returns HTTP 400 unsupported_value, so it is omitted.
DECLARE @payload  NVARCHAR(MAX);
DECLARE @response NVARCHAR(MAX);

SET @payload =
    N'{"messages":[' +
    N'{"role":"system","content":"You are a helpful assistant that answers questions by using only approved FAQ context."},' +
    N'{"role":"user","content":"' + STRING_ESCAPE(@prompt, 'json') + N'"}' +
    N']}';

EXEC sp_invoke_external_rest_endpoint
    @method     = 'POST',
    @url        = N'https://aif-lab513-2139d8.cognitiveservices.azure.com/openai/deployments/gpt-5/chat/completions?api-version=2025-04-01-preview',
    @headers    = N'{"Content-Type":"application/json"}',
    @credential = [https://aif-lab513-2139d8.cognitiveservices.azure.com],   -- TOKEN (Managed Identity), NOT an api-key
    @payload    = @payload,
    @response   = @response OUTPUT;

SELECT
    @response AS raw_response,
    COALESCE(
        JSON_VALUE(@response, '$.result.choices[0].message.content'),
        JSON_VALUE(@response, '$.choices[0].message.content'),
        @response
    ) AS ai_answer;
