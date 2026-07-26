#!/usr/bin/env python3
import os
os.environ["DATEST_REMINDER_MODE"] = "2h"
from datest_reminder_engine import main
raise SystemExit(main())
