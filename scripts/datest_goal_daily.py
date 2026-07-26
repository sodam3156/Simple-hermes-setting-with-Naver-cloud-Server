#!/usr/bin/env python3
import os
os.environ["DATEST_REMINDER_MODE"] = "daily"
from datest_reminder_engine import main
raise SystemExit(main())
