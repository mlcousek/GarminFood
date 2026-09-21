## Purpose

Give long-term use its own permanent record of milestones — consistency, volume, variety, and playful cumulative/extreme facts — paced so a multi-year user keeps discovering new ones rather than unlocking the whole catalog in the first month.

## ADDED Requirements

### Requirement: Achievements are permanent, one-time unlocks from a large, paced catalog

The system SHALL maintain a fixed catalog of at least 100 achievement definitions, each evaluated against locally available cumulative statistics, and SHALL permanently record an achievement as unlocked (with its unlock date) the first time its condition is met. An unlocked achievement SHALL NOT be re-evaluated or revoked afterward.

#### Scenario: An achievement's condition becomes true

- **WHEN** a locally computed statistic first satisfies an achievement's condition
- **THEN** that achievement is recorded as unlocked with the current date, and remains unlocked from then on regardless of later changes to the underlying statistic

#### Scenario: Catalog is paced for multi-year use

- **WHEN** the achievement catalog is inspected
- **THEN** it includes thresholds that require at least one year of sustained use to reach (e.g. a 365-day streak or an app-anniversary achievement), not only thresholds reachable within the first month

### Requirement: Lifetime cumulative statistics persist independently of capped history stores

The system SHALL track lifetime cumulative totals needed for achievement evaluation (total logs, total calories logged, the single highest-calorie nutrition-day, per-macro cumulative goal-hit-day counts, and the first-ever log date) in a persisted ledger that is not subject to the retained-history size caps of the existing usage-history or goal-status stores, so these totals remain accurate indefinitely rather than plateauing once older records roll off.

#### Scenario: Usage history exceeds its retention cap

- **WHEN** the retained usage-history store has trimmed events older than its cap
- **THEN** lifetime-total achievements (e.g. total logs ever) continue to reflect the true cumulative count, unaffected by that trimming

### Requirement: Achievements are visible on a dedicated screen with locked and unlocked state

The system SHALL present all achievements, grouped by category, showing locked achievements distinctly from unlocked ones, and showing the unlock date for each unlocked achievement.

#### Scenario: Viewing the achievements screen

- **WHEN** the user opens the achievements screen
- **THEN** every achievement in the catalog is shown, visually distinguishing locked from unlocked, with unlock dates shown for unlocked entries

### Requirement: Unlocking an achievement is a rewarded, visible moment

The system SHALL award XP and present a visible completion moment the first time an achievement unlocks, consistent with how level-ups and challenge completions are presented.

#### Scenario: An achievement unlocks during a refresh

- **WHEN** an achievement's condition first becomes true during a state refresh
- **THEN** the user sees an unlock moment and XP is awarded
