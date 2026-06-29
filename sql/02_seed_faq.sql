/* ===========================================================================
   LAB513 - 02_seed_faq.sql
   Seeds dbo.FAQ_Content with sample customer-support FAQ rows.
   Themes match the questions referenced in the lab (order tracking,
   damaged item, wrong item, returns, refunds, etc.).
   Idempotent: clears existing rows first.

   IMPORTANT (Exercise 1, Task 6): no question may contain the literal phrase
   "delivery status". That task proves keyword search
       WHERE question LIKE '%delivery status%'   -> returns 0 rows
   while semantic search for "Where can I check my delivery status?" still
   finds "How do I track my order?". Do not add a question with that phrase.
   =========================================================================== */

DELETE FROM dbo.FAQ_Embeddings;
DELETE FROM dbo.FAQ_Content;
GO

INSERT INTO dbo.FAQ_Content (faq_id, category, question, answer) VALUES
(1,  N'Orders',   N'How do I track my order?',
    N'You can track your order from the Orders page in your account. Select the order to see its current status and the latest tracking updates.'),
(2,  N'Orders',   N'Will I get an order confirmation?',
    N'Yes. After you place an order, we send an order confirmation email with your order number and a summary of your purchase.'),
(3,  N'Orders',   N'Can I change my delivery address after ordering?',
    N'You can update the delivery address from the order details page while the order is still Processing. Once it ships, the address can no longer be changed.'),
(4,  N'Orders',   N'How do I cancel an order?',
    N'You can cancel an order from the order details page while it is still Processing. After it ships, please start a return instead.'),
(5,  N'Returns',  N'How do I return a damaged item?',
    N'If your item arrived damaged, open the order, select Return, and choose Damaged as the reason. We will send a prepaid shipping label and arrange a replacement or refund.'),
(6,  N'Returns',  N'What if I received the wrong item?',
    N'If you received the wrong item, start a return from the order and select Wrong item received. We will ship the correct item and cover the return postage.'),
(7,  N'Returns',  N'What is your return policy?',
    N'Most items can be returned within 30 days of delivery in their original condition. Some categories such as final-sale items are not eligible.'),
(8,  N'Returns',  N'How long do refunds take?',
    N'Refunds are issued to your original payment method within 5 to 7 business days after we receive and inspect the returned item.'),
(9,  N'Shipping', N'How much does shipping cost?',
    N'Standard shipping is free on orders over 50. Orders below that amount have a flat standard shipping fee shown at checkout.'),
(10, N'Shipping', N'Do you ship internationally?',
    N'We ship to most countries. Shipping cost and delivery time are calculated at checkout based on the destination.'),
(11, N'Payments', N'What payment methods do you accept?',
    N'We accept major credit and debit cards and most common digital wallets. The available options are shown at checkout.'),
(12, N'Payments', N'Why was my payment declined?',
    N'A payment can be declined due to an incorrect card number, insufficient funds, or a bank security hold. Verify your details or contact your bank, then try again.'),
(13, N'Account',  N'How do I reset my password?',
    N'Select Forgot password on the sign-in page and follow the emailed link to set a new password.'),
(14, N'Account',  N'How do I contact customer support?',
    N'You can reach customer support from the Help Center by starting a chat or submitting a request, and we will respond as soon as possible.');
GO

SELECT COUNT(*) AS faq_count FROM dbo.FAQ_Content;
GO
