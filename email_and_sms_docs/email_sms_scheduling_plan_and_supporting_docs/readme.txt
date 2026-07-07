Email & SMS Scheduling — Plan & Supporting Docs

Confluence (SBE - Admin Panel → Email and SMS Scheduling, Dynamic Receipient Resolution Engine, Integrate an SMS provider):
  Predefined: https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3859742741/SBE+-+Admin+Panel#Email-and-SMS-Scheduling
  Custom:     https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3859742741/SBE+-+Admin+Panel#Email-and-SMS-Scheduling.1

Files:
  1. EMAIL_SMS_SCHEDULING_STORY.md            - Refined user story, written because the original user stories were not specific enough against the client template list.
                                                 Re-derives scheduling from that list: 3 schedule kinds + acceptance criteria, with client cues mapped to schedule shapes.
  2. EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md - Engineering build plan: tables, schedulability marking, worker poller, end-to-end logic.
  3. EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md  - Dev reference for wiring a non-seeded template + schedule (fields, decision tree, examples).
  4. EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md     - Scheduling-specific open items / deferrals / findings (SCH-1..SCH-7).
  5. EMAIL_SMS_SCHEMA_DIAGRAMS.md             - Explainer for the two ER diagrams (existing vs proposed).
  6. EMAIL_SMS_SCHEMA_EXISTING.svg            - ER diagram of the notification schema today.
  7. EMAIL_SMS_SCHEMA_PROPOSED.svg            - ER diagram of the proposed schema (green = new).
  8. EMAIL_SMS_SCHEDULING_ARCHITECTURE.svg    - Three-layer architecture (admin / Postgres / worker).
  9. EMAIL_SMS_SCHEDULING_FLOWCHART.svg       - End-to-end runtime flow, config to dispatch.
 10. EMAIL_SMS_Consolidated_Template_List.xlsx - 52-row consolidated template list with provenance + scheduling legend.
 11. EMAIL_SMS_KNOWN_ISSUES.md                 - List of known issues uptill sprint 4 development for EMAIL and SMS management module
 12. EMAIL_SMS_77.9_DYNAMIC_RECIPIENT_RESOLUTION_GAP_ANALYSIS.md - Story Gap Analysis for DRR
 13. EMAIL_SMS_76.8_SMS_PROVIDER_INTEGRATION_GAP_ANALYSIS.md - Story Gap Analysis for SMS Integration