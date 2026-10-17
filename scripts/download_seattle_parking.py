"""
Download a filtered slice of Seattle's "2025 Paid Parking Occupancy" dataset
using the SODA2 API (the "resource" endpoint), in pages of 50,000 rows.

Usage:
    pip install requests
    python download_seattle_parking.py

The script FIRST counts the matching rows and asks before downloading.
Run it once per week, changing START, END and OUT_FILE in the SETTINGS block
(the two weeks used in this project are listed there). Save the CSVs in data/raw/.
"""

import sys
import time

import requests

# ---------------- SETTINGS (edit here) ----------------
DATASET_ID = "7c2e-uany"
BASE_URL = f"https://cos-data.seattle.gov/resource/{DATASET_ID}"

# Weeks used in this project (each window runs Monday to Sunday; the dataset
# has no Sunday rows, so data ends on Saturday):
#   Week 1: START = "2025-06-02T00:00:00", END = "2025-06-08T23:59:59"
#           OUT_FILE = "seattle_week1_2025-06-02.csv"   (1,921,428 rows)
#   Week 2: START = "2025-06-30T00:00:00", END = "2025-07-06T23:59:59"
#           OUT_FILE = "seattle_week2_2025-06-30.csv"   (1,571,355 rows)
START = "2025-06-30T00:00:00"
END = "2025-07-06T23:59:59"
AREAS = [
    "Commercial Core",
    "South Lake Union",
    "Fremont",
    "Uptown",
    "Columbia City",
]

OUT_FILE = "seattle_week2_2025-06-30.csv"
PAGE_SIZE = 50000               # SODA2 maximum per request
WARN_ABOVE_ROWS = 3_000_000     # ask for extra confirmation above this
APP_TOKEN = ""                  # optional free token from the portal; can stay empty
# Stable ordering is needed so pages do not overlap or skip rows.
ORDER = ":id"
# ------------------------------------------------------

area_list = ",".join(f"'{a}'" for a in AREAS)
WHERE = (
    f"occupancydatetime between '{START}' and '{END}' "
    f"AND paidparkingarea in({area_list})"
)

HEADERS = {"X-App-Token": APP_TOKEN} if APP_TOKEN else {}


def get(url, params, retries=3):
    """GET with simple retry; prints the server message if it fails."""
    for attempt in range(1, retries + 1):
        try:
            resp = requests.get(url, params=params, headers=HEADERS, timeout=180)
            if resp.status_code == 200:
                return resp
            print(f"[HTTP {resp.status_code}] {resp.text[:500]}")
            if resp.status_code in (400, 404):
                # Bad query or wrong field name: retrying will not help.
                sys.exit("Stopping: check the field names / filter above.")
        except requests.RequestException as exc:
            print(f"[network error, attempt {attempt}/{retries}] {exc}")
        time.sleep(3 * attempt)
    sys.exit("Giving up after repeated errors.")


def count_rows():
    resp = get(f"{BASE_URL}.json", {"$select": "count(*)", "$where": WHERE})
    return int(resp.json()[0]["count"])


def download(total):
    offset = 0
    written = 0
    first_page = True
    with open(OUT_FILE, "wb") as f:
        while True:
            resp = get(
                f"{BASE_URL}.csv",
                {
                    "$where": WHERE,
                    "$order": ORDER,
                    "$limit": PAGE_SIZE,
                    "$offset": offset,
                },
            )
            header, _, body = resp.content.partition(b"\n")
            if not body.strip():
                break
            if first_page:
                f.write(header + b"\n")
                first_page = False
            f.write(body if body.endswith(b"\n") else body + b"\n")
            written += body.count(b"\n")
            offset += PAGE_SIZE
            print(f"  downloaded ~{written:,} / {total:,} rows")
            if offset >= total:
                break
    return written


def main():
    print("Filter:", WHERE)
    total = count_rows()
    print(f"\nMatching rows: {total:,}")

    if total == 0:
        sys.exit("No rows matched. Check dates and area names.")

    if total > WARN_ABOVE_ROWS:
        print(f"That is more than {WARN_ABOVE_ROWS:,} rows.")
        if input("Download anyway? (y/n): ").strip().lower() != "y":
            sys.exit("Stopped. Narrow the filter in the SETTINGS section.")
    else:
        if input("Download now? (y/n): ").strip().lower() != "y":
            sys.exit("Stopped.")

    written = download(total)
    print(f"\nDone. About {written:,} rows saved to {OUT_FILE}")


if __name__ == "__main__":
    main()
