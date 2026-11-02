// GET /api/admin/dashboard
import type { PlatformKey, RunTotals, Tone } from "../types";

export interface HealthDetail {
  label: string;
  value: string | null;
  /** Shown relative to now when set; otherwise `value`. */
  time: string | null;
  strong: boolean;
}

export interface HealthCheck {
  key: "database" | "job_queue" | "slack_api" | "teams_api" | string;
  label: string;
  /** "database", "stack", "hash" or "people" */
  icon: string;
  status: "ok" | "warn" | "error" | string;
  status_label: string;
  status_tone: Tone;
  details: HealthDetail[];
}

export interface AdminStats {
  standups_total: number;
  standups_active: number;
  standups_paused: number;
  active_people: number;
  active_participants: number;
  responses_last_24h: number;
  completed_last_24h: number;
  users_active: number;
  users_admin: number;
  standup_owners: number;
}

export interface ResponseStatusTotal {
  status: string;
  label: string;
  count: number;
  percent: number;
  tone: Tone;
}

export interface AdminUser {
  id: number;
  name: string;
  email: string;
  placeholder_email: boolean;
  subtitle: string;
  identities: { platform: PlatformKey; platform_user_id: string }[];
  avatar_url: string | null;
  admin: boolean;
  access_label: string;
  /** "info" for admins, null otherwise. */
  access_tone: Tone;
  owned_standups_count: number;
  owned_standups_label: string;
  last_signed_in_at: string | null;
  active: boolean;
  status_label: string;
  status_tone: Tone;
}

export interface AuditLogEntry {
  id: number;
  action: string;
  action_label: string;
  actor_name: string;
  actor_avatar_url: string | null;
  auditable_type: string | null;
  auditable_label: string;
  auditable_id: number | null;
  created_at: string | null;
}

export interface FailedReport {
  id: number;
  standup_id: number;
  standup_name: string | null;
  error_message: string;
  requested_at: string | null;
}

export interface AdminDashboard {
  health: { status: "healthy" | "degraded" | "unhealthy" | string; status_label: string; status_tone: Tone; checked_at: string | null };
  health_checks: HealthCheck[];
  stats: AdminStats;
  activity_days: number;
  daily_activity: RunTotals[];
  daily_activity_has_pending: boolean;
  response_totals: { total: number; statuses: ResponseStatusTotal[] };
  users: AdminUser[];
  audit_logs: AuditLogEntry[];
  failed_reports: FailedReport[];
}
