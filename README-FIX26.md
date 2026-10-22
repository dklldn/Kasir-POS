FIX26 - Printer/Drawer Reliability

Changes:
- Removed unnecessary non-null assertions from firstError.
- Added _printerStabilizeDelay() helper (350 ms) for use immediately after
  successful printer connection and before ESC/POS transmission.
- No changes to transaction/ticket/payment data structures.
- No changes to owner permission logic.

IMPORTANT:
This build is conservative because the exact printer package/API and hardware
transport determine whether the correct transport is Bluetooth Classic, BLE,
USB, or network. The helper is intentionally non-invasive.

Recommended test order:
1. Printer connection.
2. Uji Struk (print only).
3. Uji Laci (drawer only).
4. Ticket -> Bayar.
5. Pemasukan/Pengeluaran.
