FIX27 - Receipt print reliability + cash drawer

Changes:
- FIX26 printer stabilization delay is now actually applied after every successful connection.
- Payment receipt printing keeps the existing ESC/POS path and retries once with a lightweight text-only receipt if the full receipt fails.
- Cash drawer remains permission-controlled and is opened only after the receipt print succeeds.
- Transaction, ticket, owner permission, cash management, and dashboard logic are unchanged.

Test order:
1. Kelola -> Printer POS -> connect printer.
2. Uji Struk.
3. Uji Laci.
4. Transaksi -> Bayar -> verify receipt then drawer.
5. Tiket tersimpan -> Bayar -> verify receipt then drawer.
