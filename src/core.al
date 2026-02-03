module authprocessor.core

record incidentInformation {
    sys_id String @optional,
    status String @optional,
    data Any @optional,
    category String @optional,
    ai_status String @optional,
    ai_processor String @optional,
    requires_human Boolean @optional,
    ai_reason String @optional,
    resolution String @optional
}

event handlePasswordReset {
    userEmail Email,
    resetMethod @enum("email_link", "temp_password", "admin_reset") @optional
}

workflow handlePasswordReset {
    console.log("++PASSWORD_RESET++ " + handlePasswordReset.userEmail)
}

event handleMfaIssue {
    userEmail Email,
    issueType @enum("lost_device", "app_issue", "sms_not_received", "backup_codes") @optional
}

workflow handleMfaIssue {
    console.log("++MFA_ISSUE++ " + handleMfaIssue.userEmail)
}

event handleAccountLockout {
    userEmail Email,
    lockoutReason @enum("failed_attempts", "security_alert", "policy_violation", "unknown") @optional
}

workflow handleAccountLockout {
    console.log("++ACCOUNT_LOCKOUT++ " + handleAccountLockout.userEmail)
}

agent passwordResetHandler {
    instruction "Extract userEmail and resetMethod from context and call handlePasswordReset.",
    tools "authprocessor.core/handlePasswordReset"
}

agent mfaIssueHandler {
    instruction "Extract userEmail and issueType from context and call handleMfaIssue.",
    tools "authprocessor.core/handleMfaIssue"
}

agent accountLockoutHandler {
    instruction "Extract userEmail and lockoutReason from context and call handleAccountLockout.",
    tools "authprocessor.core/handleAccountLockout"
}

agent authTriager {
    instruction "Classify the authentication issue into PASSWORD_RESET, MFA_ISSUE, ACCOUNT_LOCKOUT, or UNKNOWN.
Only return one of the strings [PASSWORD_RESET, MFA_ISSUE, ACCOUNT_LOCKOUT, UNKNOWN] and nothing else."
}

flow authOrchestrator {
    authTriager --> "PASSWORD_RESET" passwordResetHandler
    authTriager --> "MFA_ISSUE" mfaIssueHandler
    authTriager --> "ACCOUNT_LOCKOUT" accountLockoutHandler
    authTriager --> "UNKNOWN" {servicenow/incident {sys_id? incidentInformation.sys_id, ai_status "failed-to-process", requires_human true}}
    passwordResetHandler --> {servicenow/incident {sys_id? incidentInformation.sys_id, ai_status "processed"}}
    mfaIssueHandler --> {servicenow/incident {sys_id? incidentInformation.sys_id, ai_status "processed"}}
    accountLockoutHandler --> {servicenow/incident {sys_id? incidentInformation.sys_id, ai_status "processed"}}
}

@public agent authOrchestrator {
    role "You are an authentication and identity management specialist."
}

workflow @after update:servicenow/incident {
    if (servicenow/incident.category == "AUTH" or servicenow/incident.ai_processor == "auth") {
        {incidentInformation {
            sys_id servicenow/incident.sys_id,
            status servicenow/incident.state,
            data servicenow/incident.data,
            category servicenow/incident.category,
            ai_status servicenow/incident.ai_status,
            ai_processor servicenow/incident.ai_processor,
            requires_human servicenow/incident.requires_human,
            ai_reason servicenow/incident.ai_reason,
            resolution servicenow/incident.resolution
        }}

        {authOrchestrator {message servicenow/incident}}
    }
}
