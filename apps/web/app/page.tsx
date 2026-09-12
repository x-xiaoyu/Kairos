"use client";

import { useEffect, useMemo, useState } from "react";

type Risk = "safe" | "warning" | "high" | "critical";
type Task = { id: string; title: string; goal: string; deadline: string | null; estimated_minutes: number; priority: number; status: string; cognitive_load: string; interruptible: boolean; deadline_type: string };
type PlanItem = { task: Task; start: string; end: string; latest_safe_start: string | null; risk: Risk; explanation: string };

const future = (hours: number, minutes = 0) => new Date(Date.now() + (hours * 60 + minutes) * 60000).toISOString();
const seed: Task[] = [
  { id: "proposal", title: "Finish launch proposal", goal: "Launch thoughtfully", deadline: future(4), estimated_minutes: 90, priority: 5, status: "todo", cognitive_load: "high", interruptible: false, deadline_type: "hard" },
  { id: "research", title: "Review user interviews", goal: "Know our users", deadline: future(8), estimated_minutes: 45, priority: 4, status: "todo", cognitive_load: "high", interruptible: true, deadline_type: "soft" },
  { id: "email", title: "Reply to partner email", goal: "Keep momentum", deadline: future(6), estimated_minutes: 20, priority: 3, status: "todo", cognitive_load: "low", interruptible: true, deadline_type: "soft" },
  { id: "outline", title: "Outline tomorrow's demo", goal: "Launch thoughtfully", deadline: future(28), estimated_minutes: 35, priority: 3, status: "todo", cognitive_load: "medium", interruptible: true, deadline_type: "soft" },
];

const profile = { wake_time: "07:30:00", sleep_time: "23:00:00", focus_block_minutes: 45, peak_energy_start: "09:00:00", peak_energy_end: "12:00:00", focus_duration_adjustment: 1, estimate_adjustment: 1 };
const fmt = (value: string | null) => value ? new Intl.DateTimeFormat("en", { hour: "numeric", minute: "2-digit" }).format(new Date(value)) : "Flexible";
type DayEvent = { id: number; time: Date; action: string; task: string; detail: string };

function localPlan(tasks: Task[]): PlanItem[] {
  let cursor = Date.now();
  return tasks.filter(t => t.status !== "complete").sort((a, b) => b.priority - a.priority).map((task) => {
    const start = new Date(cursor); const end = new Date(cursor + task.estimated_minutes * 60000); cursor = end.getTime() + 5 * 60000;
    const latest = task.deadline ? new Date(new Date(task.deadline).getTime() - (task.estimated_minutes + 15) * 60000) : null;
    const slack = latest ? latest.getTime() - Date.now() : Infinity;
    const risk: Risk = slack <= 0 ? "critical" : slack < 30 * 60000 ? "high" : slack < 90 * 60000 ? "warning" : "safe";
    return { task, start: start.toISOString(), end: end.toISOString(), latest_safe_start: latest?.toISOString() || null, risk, explanation: risk === "critical" ? "Start now to protect the deadline; lower-priority work may need to move." : "Scheduled by deadline, priority, and the time still available today." };
  });
}

export default function Home() {
  const [tasks, setTasks] = useState(seed);
  const [items, setItems] = useState<PlanItem[]>(() => localPlan(seed));
  const [selected, setSelected] = useState(seed[0].id);
  const [seconds, setSeconds] = useState(seed[0].estimated_minutes * 60);
  const [running, setRunning] = useState(false);
  const [focusOpen, setFocusOpen] = useState(false);
  const [justStarted, setJustStarted] = useState(false);
  const [reviewOpen, setReviewOpen] = useState(false);
  const [events, setEvents] = useState<DayEvent[]>([{ id: 1, time: new Date(), action: "Plan ready", task: "Today’s plan", detail: "Kairos arranged your first realistic path for the day." }]);
  const [routines, setRoutines] = useState([{ name: "LeetCode practice", done: false, streak: 6 }, { name: "Exercise", done: false, streak: 3 }, { name: "Mock interview", done: false, streak: 1 }]);
  const [notice, setNotice] = useState("Your day is protected. You have room to finish what matters.");

  const replan = async (next: Task[]) => {
    setTasks(next);
    try {
      const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000"}/plan`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ now: new Date().toISOString(), tasks: next, commitments: [], profile }) });
      if (!response.ok) throw new Error();
      const data = await response.json(); setItems(data.items); setNotice(data.summary);
    } catch { setItems(localPlan(next)); setNotice("Replanned locally — the demo stays useful even while the AI service is offline."); }
  };

  useEffect(() => { if (!running) return; const timer = setInterval(() => setSeconds(s => { if (s <= 1) { setRunning(false); return 0; } return s - 1; }), 1000); return () => clearInterval(timer); }, [running]);
  const active = useMemo(() => items.find(i => i.task.id === selected) || items[0], [items, selected]);
  useEffect(() => { if (active && !running) setSeconds(active.task.estimated_minutes * 60); }, [active?.task.id, active?.task.estimated_minutes]);
  const addEvent = (action: string, task: string, detail: string) => setEvents(current => [...current, { id: Date.now() + Math.random(), time: new Date(), action, task, detail }]);
  const complete = (id: string) => { const finished = tasks.find(t => t.id === id); const next = tasks.map(t => t.id === id ? { ...t, status: "complete" } : t); replan(next); if (finished) addEvent("Completed", finished.title, `${finished.estimated_minutes} minute focus estimate completed.`); setSelected(next.find(t => t.status !== "complete" && t.id !== id)?.id || ""); };
  const postpone = (id: string) => { const postponed = tasks.find(t => t.id === id); const next = tasks.map(t => t.id === id ? { ...t, priority: Math.max(1, t.priority - 1) } : t); replan(next); if (postponed) addEvent("Postponed", postponed.title, "Moved back so the next safest task can lead."); setNotice("Plan adjusted. This task moved back; the next safest action is now first."); };
  const adjust = (id: string, field: "estimated_minutes" | "priority", delta: number) => { const changed = tasks.find(t => t.id === id); replan(tasks.map(t => t.id === id ? { ...t, [field]: field === "priority" ? Math.min(5, Math.max(1, t[field] + delta)) : Math.min(720, Math.max(5, t[field] + delta)) } : t)); if (changed) addEvent(field === "priority" ? "Priority changed" : "Duration changed", changed.title, `${delta > 0 ? "Increased" : "Decreased"} ${field === "priority" ? "priority" : "duration"}.`); };
  const startFocus = (id: string) => {
    const task = tasks.find(item => item.id === id);
    setTasks(current => current.map(t => t.id === id ? { ...t, status: "in_progress" } : t));
    setNotice(`Focus started: ${task?.title || "your task"}. The timer is running now.`);
    if (task) addEvent("Focus started", task.title, `${task.estimated_minutes} minute countdown started.`);
    setFocusOpen(true);
    setJustStarted(true);
    setRunning(true);
    window.setTimeout(() => setJustStarted(false), 1200);
  };
  const ring = `${Math.floor(seconds / 60).toString().padStart(2,"0")}:${(seconds % 60).toString().padStart(2,"0")}`;
  const completedTasks = tasks.filter(task => task.status === "complete");

  return <main>
    {focusOpen && active && <div className="focus-overlay" role="dialog" aria-modal="true" aria-label="Focus countdown">
      <div className={`focus-stage ${justStarted ? "just-started" : ""}`}>
        {justStarted && <div className="start-burst"><span>✦</span><strong>Focus starts!</strong></div>}
        <button className="close-focus" aria-label="Close focus mode" onClick={() => { setFocusOpen(false); setRunning(false); }}>×</button>
        <p className="focus-kicker"><i/> {running ? "FOCUSING NOW" : "FOCUS PAUSED"}</p>
        <h2>{active.task.title}</h2>
        <div className="giant-timer">{ring}</div>
        <p className="focus-encouragement">{running ? "Stay with this one thing. Everything else can wait." : "Your time is saved. Resume when you’re ready."}</p>
        <div className="focus-controls"><button className="overlay-primary" onClick={() => setRunning(!running)}>{running ? "Ⅱ  Pause" : "▶  Resume"}</button><button onClick={() => { setRunning(false); setFocusOpen(false); }}>End focus</button><button onClick={() => { complete(active.task.id); setRunning(false); setFocusOpen(false); }}>Complete task</button></div>
      </div>
    </div>}
    {reviewOpen && <div className="review-overlay" role="dialog" aria-modal="true" aria-label="Review my day" onClick={() => setReviewOpen(false)}>
      <section className="review-panel" onClick={event => event.stopPropagation()}>
        <button className="close-focus" aria-label="Close day review" onClick={() => setReviewOpen(false)}>×</button>
        <p className="eyebrow">YOUR MOMENTUM</p><h2>Review your day</h2><p className="review-intro">Progress is a pattern, not a perfect streak. Here’s what your effort is building.</p>
        <div className="review-stats"><div><strong>{completedTasks.length}</strong><span>completed today</span></div><div><strong>{completedTasks.reduce((sum, task) => sum + task.estimated_minutes, 0)}m</strong><span>focused today</span></div><div><strong>{events.filter(event => event.action === "Focus started").length}</strong><span>focus sessions</span></div><div><strong>{routines.filter(routine => routine.done).length}/{routines.length}</strong><span>routines done</span></div></div>
        <div className="activity-log"><div className="log-heading"><strong>Today’s timeline</strong><span>{new Intl.DateTimeFormat("en", { weekday: "long", month: "short", day: "numeric" }).format(new Date())}</span></div>{[...events].reverse().map(event => <div className="log-row" key={event.id}><time>{new Intl.DateTimeFormat("en", { hour: "numeric", minute: "2-digit" }).format(event.time)}</time><i/><div><strong>{event.action}</strong><h3>{event.task}</h3><p>{event.detail}</p></div></div>)}</div>
        <div className="review-note"><span>✦</span><p><strong>{completedTasks.length ? "You created momentum today." : "Your next session starts today’s story."}</strong><br/>{completedTasks.length ? `${completedTasks.length} task${completedTasks.length > 1 ? "s" : ""} completed. Keep the rest of the day humane.` : "One honest focus block is enough to make today count."}</p></div>
      </section>
    </div>}
    <header><a className="brand" href="#"><span className="mark">K</span><span>Kairos</span></a><div className="date"><span>{new Intl.DateTimeFormat("en", { weekday: "long", month: "long", day: "numeric" }).format(new Date())}</span><button aria-label="Profile">XY</button></div></header>
    <section className="hero"><div><p className="eyebrow">GOOD MORNING</p><h1>There’s a right time<br/>for everything.</h1><p className="sub">We’ve done the arithmetic. Here’s the shape of your day.</p></div><div className="day-score"><div className="score-ring"><strong>82</strong><span>DAY<br/>FIT</span></div><p>Comfortable<br/><span>2h 10m buffer</span></p></div></section>
    <div className="notice"><span>✦</span><p>{notice}</p><button onClick={() => setNotice("")}>×</button></div>
    <section className="grid">
      <div className="plan"><div className="section-head"><div><p className="eyebrow">TODAY’S PATH</p><h2>What matters now</h2></div><button className="ghost" onClick={() => setReviewOpen(true)}>▦ Review my day</button></div>
        <div className="timeline">{items.map((item, index) => <article key={item.task.id} className={`task ${selected === item.task.id ? "active" : ""}`} onClick={() => setSelected(item.task.id)}>
          <div className="time">{fmt(item.start)}<span>{item.task.estimated_minutes}m</span></div><div className={`dot ${item.risk}`}>{index === 0 ? "▶" : ""}</div>
          <div className="task-body"><div className="task-title"><h3>{item.task.title}</h3><span className={`pill ${item.risk}`}>{item.risk === "safe" ? "On track" : item.risk}</span></div><p>{item.task.goal} · {item.task.cognitive_load} energy</p>
            {selected === item.task.id && <div className="task-detail"><p>{item.explanation}</p><div className="adjusters"><span>Duration <button onClick={(e) => {e.stopPropagation(); adjust(item.task.id,"estimated_minutes",-5)}}>−</button><b>{item.task.estimated_minutes}m</b><button onClick={(e) => {e.stopPropagation(); adjust(item.task.id,"estimated_minutes",5)}}>+</button></span><span>Priority <button onClick={(e) => {e.stopPropagation(); adjust(item.task.id,"priority",-1)}}>−</button><b>{item.task.priority}</b><button onClick={(e) => {e.stopPropagation(); adjust(item.task.id,"priority",1)}}>+</button></span></div><div className="actions"><button className="primary" onClick={(e) => { e.stopPropagation(); startFocus(item.task.id); }}>Start focus</button><button onClick={(e) => { e.stopPropagation(); postpone(item.task.id); }}>Postpone</button><button onClick={(e) => { e.stopPropagation(); complete(item.task.id); }}>Mark done</button></div></div>}
          </div></article>)}</div>
      </div>
      <aside><div className={`focus-card ${running ? "is-running" : ""}`}><div className="focus-heading"><p className="eyebrow">FOCUS WINDOW</p>{running && <span className="live-status"><i/> FOCUSING NOW</span>}</div><h2>{active?.task.title || "Day complete"}</h2><div className="timer"><span className="timer-halo"/><svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="53"/><circle className="progress" cx="60" cy="60" r="53"/></svg><strong>{ring}</strong></div><p className="calm">{running ? "You’re in focus mode. Stay with this one thing." : "One thing at a time. That’s enough."}</p><button className="focus-button" disabled={!active} onClick={() => active && (running ? setFocusOpen(true) : startFocus(active.task.id))}>{running ? "Open focus screen" : seconds === 0 ? "Finished" : "Begin focus"}</button></div>
        <div className="safe-card"><p className="eyebrow">LATEST SAFE START</p><div className="safe-time"><strong>{fmt(active?.latest_safe_start || null)}</strong><span className={active?.risk || "safe"}>{active?.risk || "safe"}</span></div><p>{active?.latest_safe_start ? `Starting by ${fmt(active.latest_safe_start)} keeps the rest of your day workable.` : "No hard edge on this task."}</p><div className="risk-track"><i></i><b></b></div><div className="labels"><span>Now</span><span>Warning</span><span>Too late</span></div></div>
        <div className="routine-card"><div><p className="eyebrow">DAILY ROUTINES</p><h2>Keep your rhythm</h2></div>{routines.map((routine, index) => <button className={routine.done ? "routine done" : "routine"} key={routine.name} onClick={() => { setRoutines(current => current.map((item, itemIndex) => itemIndex === index ? { ...item, done: !item.done } : item)); addEvent(routine.done ? "Routine reopened" : "Routine completed", routine.name, routine.done ? "Marked as not complete yet." : `${routine.streak + 1} day streak protected.`); }}><span>{routine.done ? "✓" : ""}</span><b>{routine.name}</b><small>{routine.streak + (routine.done ? 1 : 0)} day streak</small></button>)}</div>
      </aside>
    </section>
    <footer><span>KAIROS</span><p>Know when it’s time to start.</p><span>Adaptive plan · Local first</span></footer>
  </main>;
}
