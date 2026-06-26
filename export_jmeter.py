# SPDX-FileCopyrightText: 2023-present Plane Software, Inc.
# SPDX-License-Identifier: LicenseRef-Plane-Commercial
#
# Licensed under the Plane Commercial License (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# https://plane.so/legals/eula
#
# DO NOT remove or modify this notice.
# NOTICE: Proprietary and confidential. Unauthorized use or distribution is prohibited.

"""
Export a JMeter-ready CSV (email, password, ws_slug, project_id, state_id,
member_id) for seeded users in a workspace.

member_id is the user's own User id — the value the work-item `assignee_ids`
field expects. The JMeter flows pool these across rows (in a setUp step) and
randomly pick assignees from the CSV instead of calling GET /members/.

Rows are emitted round-robin by project (one row per project in turn) so any
prefix of N rows covers N distinct projects. The flows bind one row per VU
sequentially, so this keeps N VUs spread across N projects and avoids funneling
concurrent work-item creates onto one project's per-project advisory lock.

Use this after `seed_project_at_scale` has run, when you need a CSV that maps
each user to a workspace + project + state the JMeter test plan can log in to.
Reads only the DB — does NOT touch users/projects/issues.

Example:
  python manage.py export_jmeter_csv \\
    --workspace_slug seedws1 \\
    --password <password printed by the seed run> \\
    --output /code/jmeter-seedws1.csv
"""

# Python imports
import csv
import os
import random
from collections import defaultdict

# Django imports
from django.core.management.base import BaseCommand, CommandError

# Module imports
from plane.db.models import Project, ProjectMember, State, Workspace


class Command(BaseCommand):
    help = (
        "Export a JMeter-ready CSV (email,password,ws_slug,project_id,state_id,member_id) "
        "from existing seeded data. Default: ONE row per user (random project + "
        "state picked per user) — avoids the cartesian-product blow-up and "
        "guarantees a JMeter thread can't collide with itself on the same email. "
        "Pass --rows_per_user 0 to emit the full (user × project) cartesian, or "
        "any positive N to sample N projects per user."
    )

    def add_arguments(self, parser):
        parser.add_argument("--workspace_slug", type=str, required=True)
        parser.add_argument(
            "--password",
            type=str,
            required=True,
            help="Plaintext password written to every row (must match what was used at seed time).",
        )
        parser.add_argument(
            "--project_identifier",
            type=str,
            default="",
            help="Restrict to one project. Default: all projects in the workspace.",
        )
        parser.add_argument(
            "--email_filter",
            type=str,
            default="@seed.plane.so",
            help="Substring match on user.email. Default: '@seed.plane.so' (filters to seeded users).",
        )
        parser.add_argument(
            "--state_name",
            type=str,
            default="Todo",
            help="Name of the state to write into state_id. Pass 'random' to pick per row. Default: Todo.",
        )
        parser.add_argument(
            "--output",
            type=str,
            default="",
            help=(
                "CSV output path. Defaults to ./jmeter-<workspace_slug>.csv "
                "(or ./jmeter-<ws>-<proj>.csv when --project_identifier is set)."
            ),
        )
        parser.add_argument(
            "--rows_per_user",
            type=int,
            default=1,
            help=(
                "Number of rows per user. Default 1 — pick one random project per user, "
                "guaranteeing each user appears exactly once. Pass 0 to emit the full "
                "(user × project) cartesian product, or any N > 1 to sample N projects "
                "per user."
            ),
        )
        parser.add_argument(
            "--seed",
            type=int,
            default=None,
            help="Seed the RNG so --rows_per_user / random state selection are reproducible.",
        )

    def handle(self, *args, **options):
        if options["seed"] is not None:
            random.seed(options["seed"])

        ws = Workspace.objects.filter(slug=options["workspace_slug"]).first()
        if not ws:
            raise CommandError(f"Workspace '{options['workspace_slug']}' not found")

        proj_qs = Project.objects.filter(workspace=ws)
        if options["project_identifier"]:
            proj_qs = proj_qs.filter(identifier=options["project_identifier"].strip().upper())
        projects = list(proj_qs.order_by("identifier"))
        if not projects:
            raise CommandError(
                f"No matching projects in workspace '{ws.slug}'"
                + (f" with identifier '{options['project_identifier']}'." if options["project_identifier"] else ".")
            )

        # state lookup: either fixed-by-name or random-per-row
        state_random = options["state_name"].strip().lower() == "random"
        state_by_project: dict = {}
        states_by_project_id: dict = {}
        for p in projects:
            sids = list(State.objects.filter(project=p).values_list("id", flat=True))
            if not sids:
                raise CommandError(f"Project {p.identifier} has no states; can't pick a state_id.")
            states_by_project_id[p.id] = sids
            if not state_random:
                named = State.objects.filter(project=p, name=options["state_name"]).values_list("id", flat=True).first()
                state_by_project[p.id] = named or sids[0]

        # Memberships → (email, project_id) pairs.
        email_filter = options["email_filter"].strip()
        pm_qs = ProjectMember.objects.filter(
            workspace=ws,
            project_id__in=[p.id for p in projects],
            is_active=True,
            deleted_at__isnull=True,
        )
        if email_filter:
            pm_qs = pm_qs.filter(member__email__icontains=email_filter)
        pairs = list(
            pm_qs.order_by("member__email", "project__identifier").values_list(
                "member_id", "member__email", "project_id"
            )
        )
        if not pairs:
            raise CommandError(
                f"No ProjectMember rows matched (workspace={ws.slug}, email_filter='{email_filter}'). "
                "Check that the seed has actually run and that --email_filter matches the seeded domain."
            )

        # Group by user; optionally sample per-user. member_id (the user's own
        # User id) is constant per email, so track it in a side map.
        by_user: dict = defaultdict(list)
        member_id_by_email: dict = {}
        for member_id, email, pid in pairs:
            by_user[email].append(pid)
            member_id_by_email[email] = member_id

        cap = options["rows_per_user"]
        if cap > 0:
            for email, pids in by_user.items():
                if len(pids) > cap:
                    by_user[email] = random.sample(pids, cap)

        # Default output path
        out_path = options["output"].strip()
        if not out_path:
            if options["project_identifier"]:
                out_path = os.path.join(
                    os.getcwd(),
                    f"jmeter-{ws.slug}-{options['project_identifier'].strip().lower()}.csv",
                )
            else:
                out_path = os.path.join(os.getcwd(), f"jmeter-{ws.slug}.csv")

        # Emit rows round-robin by project so any prefix of N rows covers N DISTINCT
        # projects. The JMeter flows bind one CSV row per VU sequentially
        # (shareMode.all), so a grouped-by-user emission funnels the first N VUs'
        # work-item creates onto a few hot projects -> the per-project
        # pg_advisory_xact_lock serializes those concurrent creates and they blow
        # past the 60s client timeout (only write paths fail; reads never lock).
        # One row per project in turn spreads N VUs across N distinct projects.
        # (Same ordering as loadtests/scripts/stride_users_csv.py, applied at source.)
        emails_by_project: dict = defaultdict(list)
        for email in sorted(by_user.keys()):
            for pid in by_user[email]:
                emails_by_project[pid].append(email)
        project_order = list(emails_by_project.keys())
        random.shuffle(project_order)  # reproducible when --seed is set
        pid_queues = [(pid, iter(emails_by_project[pid])) for pid in project_order]

        password = options["password"]
        n_rows = 0
        remaining = sum(len(v) for v in emails_by_project.values())
        with open(out_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["email", "password", "ws_slug", "project_id", "state_id", "member_id"])
            while remaining:
                for pid, q in pid_queues:
                    email = next(q, None)
                    if email is None:
                        continue
                    sid = random.choice(states_by_project_id[pid]) if state_random else state_by_project[pid]
                    w.writerow([email, password, ws.slug, pid, sid, member_id_by_email[email]])
                    n_rows += 1
                    remaining -= 1

        self.stdout.write(
            self.style.SUCCESS(
                f"Wrote {n_rows} rows ({len(by_user)} users × {len(projects)} project(s)) "
                f"to {out_path}"
            )
        )
