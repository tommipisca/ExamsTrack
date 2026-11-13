// Dati dell'app salvati in exams.json e deletions.json, con le stesse regole di ExamStore.swift.
// La persistenza è passata dall'esterno: file veri nell'app, memoria nei test.

import { iso, isoOf, noon } from './calendar.js';
import { decodeDeletions, decodeExamList, DecodeError, parseJSON, swiftJSON } from './codec.js';
import { balancedColorIndex, isMasterThesis, rescheduleOverdue } from './logic.js';
import { deletionsEqual, examsEqual, makeSnapshot, unique } from './sync.js';

export const DATA_FILE = 'exams.json';
export const DELETIONS_FILE = 'deletions.json';
export const CORRUPT_FILE = 'exams.corrupt.json';

export const STORE_ERRORS = {
  corruptedData: "I dati salvati erano illeggibili: sono stati spostati in exams.corrupt.json e l'elenco è ripartito da zero.",
  saveFailed: 'Impossibile salvare le modifiche.',
  readFailed: "Impossibile leggere i dati salvati. Per non sovrascriverli, le modifiche non verranno salvate: chiudi e riapri l'app.",
};

export class BackupError extends Error {
  constructor() {
    super('Il file non è un backup di ExamsTrack leggibile. I dati attuali non sono stati modificati.');
  }
}

/**
 * persistence: { readText(name) → testo o null se manca (lancia se non si legge),
 *                writeTexts([{ name, text }]) (in ordine, ciascuno atomico), rename(from, to), remove(name) }
 */
export class ExamStore {
  exams = [];
  /** Esami eliminati (id → data), salvati accanto ai dati per la sincronizzazione. */
  deletions = {};
  /** Chiave di STORE_ERRORS, oppure null. */
  lastError = null;
  #listeners = new Set();
  #persistence;
  #now;
  /** Vero se il file esiste ma non si legge: non si salva, per non sovrascriverlo. */
  #isReadBlocked = false;
  #saving = Promise.resolve();

  constructor({ persistence, now = () => new Date() }) {
    this.#persistence = persistence;
    this.#now = now;
  }

  static async open(options) {
    const store = new ExamStore(options);
    await store.#load();
    return store;
  }

  /** Chiamato a ogni cambiamento dei dati o di `lastError`. */
  subscribe(listener) {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  #emit() {
    for (const listener of this.#listeners) listener();
  }

  /** Attende la fine dei salvataggi in corso. */
  flush() {
    return this.#saving;
  }

  clearError() {
    this.lastError = null;
    this.#emit();
  }

  // MARK: Sincronizzazione

  get syncSnapshot() {
    return makeSnapshot(this.exams, this.deletions);
  }

  /** Applica il risultato di un'unione; non salva se non cambia nulla. */
  applySynced(snapshot) {
    if (examsEqual(snapshot.exams, this.exams) && deletionsEqual(snapshot.deletions, this.deletions)) return false;
    this.exams = snapshot.exams.map((exam) => ({ ...exam }));
    this.deletions = { ...snapshot.deletions };
    this.#assignMissingColors();
    this.#save();
    return true;
  }

  // MARK: Lettura

  /** Corso proposto per un nuovo esame: quello dell'ultimo esame inserito. */
  get defaultDegree() {
    return this.exams.at(-1)?.degree ?? 'triennale';
  }

  exam(id) {
    return this.exams.find((exam) => exam.id === id) ?? null;
  }

  /** Colore che riceverà il prossimo esame creato: il meno usato della tavolozza. */
  get nextColorIndex() {
    return balancedColorIndex(this.exams.map((exam) => exam.colorIndex).filter((index) => index !== null));
  }

  // MARK: Esami

  addExam(exam) {
    const created = { ...exam };
    if (created.colorIndex === null || created.colorIndex === undefined) created.colorIndex = this.nextColorIndex;
    created.modifiedAt = this.#timestamp();
    this.exams = [...this.exams, this.#normalized(created)];
    this.#save();
  }

  updateExam(exam) {
    this.#mutate(exam.id, (draft) => Object.assign(draft, structuredClone(exam)));
  }

  /** Cambia solo i dati del form, senza toccare task ed esito. */
  updateExamDetails(id, details) {
    this.#mutate(id, (exam) => {
      exam.name = details.name;
      exam.date = isoOf(details.date);
      exam.degree = details.degree;
      exam.cfu = details.cfu;
      exam.isFinalTest = details.isFinalTest;
      exam.isScheduled = details.isScheduled;
      exam.startTime = details.startTime;
    });
  }

  deleteExam(id) {
    // Sempre dopo l'ultima modifica nota, anche se l'orologio di questo dispositivo è indietro.
    const deletedAt = this.#stamp(this.exam(id)?.modifiedAt);
    this.exams = this.exams.filter((exam) => exam.id !== id);
    this.deletions = { ...this.deletions, [id]: deletedAt };
    this.#save();
  }

  // MARK: Task

  addTask(task, examID) {
    this.#mutate(examID, (exam) => exam.tasks.push({ ...task }));
  }

  /** Più task insieme, con un solo salvataggio (piano di studio). */
  addTasks(tasks, examID) {
    this.#mutate(examID, (exam) => exam.tasks.push(...tasks.map((task) => ({ ...task }))));
  }

  updateTask(task, examID) {
    this.#mutate(examID, (exam) => {
      const index = exam.tasks.findIndex((item) => item.id === task.id);
      if (index !== -1) exam.tasks[index] = { ...task };
    });
  }

  deleteTask(id, examID) {
    this.#mutate(examID, (exam) => {
      exam.tasks = exam.tasks.filter((task) => task.id !== id);
    });
  }

  /** Sposta un task a un altro giorno (mai oltre il giorno dell'esame). */
  moveTask(id, examID, day) {
    this.#mutate(examID, (exam) => {
      const task = exam.tasks.find((item) => item.id === id);
      if (task) task.dueDate = isoOf(day);
    });
  }

  /** Ridistribuisce i task in ritardo di un esame da oggi fino all'esame. */
  rescheduleOverdue(examID, today = this.#now()) {
    this.#mutate(examID, (exam) => {
      exam.tasks = rescheduleOverdue(exam, today);
    });
  }

  /** Spunta (o riapre) un task; con sotto-task, li spunta (o riapre) tutti. */
  toggleTask(id, examID) {
    this.#mutate(examID, (exam) => {
      const task = exam.tasks.find((item) => item.id === id);
      if (!task) return;
      task.isDone = !task.isDone;
      task.subtasks = (task.subtasks ?? []).map((sub) => ({ ...sub, isDone: task.isDone }));
    });
  }

  /** Spunta una voce della checklist; il task risulta fatto quando lo sono tutte. */
  toggleSubtask(id, taskID, examID) {
    this.#mutate(examID, (exam) => {
      const task = exam.tasks.find((item) => item.id === taskID);
      const sub = task?.subtasks?.find((item) => item.id === id);
      if (sub) sub.isDone = !sub.isDone;
    });
  }

  /** Segna un task come fatto (o da fare); non salva se è già in quello stato. */
  setTaskDone(id, examID, isDone = true) {
    const task = this.exam(examID)?.tasks.find((item) => item.id === id);
    if (task && task.isDone !== isDone) this.toggleTask(id, examID);
  }

  // MARK: Esito

  /** Imposta l'esito normalizzando: voto 18...30 solo se superato (default 18), lode solo con 30. */
  setOutcome(examID, passed, grade, honors) {
    this.#mutate(examID, (exam) => {
      exam.passed = passed;
      if (isMasterThesis(exam)) {
        // La tesi non ha voto né lode: solo il punteggio, che resta finché è superata.
        exam.grade = null;
        exam.honors = false;
        if (passed !== true) exam.thesisPoints = null;
      } else if (passed === true) {
        const normalized = Math.min(Math.max(grade ?? 18, 18), 30);
        exam.grade = normalized;
        exam.honors = honors && normalized === 30;
      } else {
        exam.grade = null;
        exam.honors = false;
      }
    });
  }

  /** Punteggio della tesi magistrale: da −1 a 8, a passi di mezzo punto. */
  setThesisPoints(examID, points) {
    this.#mutate(examID, (exam) => {
      exam.thesisPoints = Math.round(Math.min(Math.max(points, -1), 8) * 2) / 2;
    });
  }

  setNotes(examID, notes) {
    this.#mutate(examID, (exam) => {
      exam.notes = notes.trim();
    });
  }

  /** Voto ipotetico del simulatore (18...30), null per toglierlo. */
  setSimulatedGrade(examID, grade) {
    // Non passa da #mutate: la simulazione ha una data di modifica tutta sua.
    const index = this.exams.findIndex((exam) => exam.id === examID);
    if (index === -1) return;
    const exams = [...this.exams];
    exams[index] = {
      ...exams[index],
      simulatedGrade: grade === null ? null : Math.min(Math.max(grade, 18), 30),
      simulationModifiedAt: this.#timestamp(),
    };
    this.exams = exams;
    this.#save();
  }

  /** Toglie tutti i voti ipotetici di un corso. */
  clearSimulation(degree) {
    const stamp = this.#timestamp();
    let changed = false;
    this.exams = this.exams.map((exam) => {
      if (exam.degree !== degree || exam.simulatedGrade === null) return exam;
      changed = true;
      return { ...exam, simulatedGrade: null, simulationModifiedAt: stamp };
    });
    if (changed) this.#save();
  }

  // MARK: Backup

  /** Tutti gli esami in un file JSON da salvare fuori dall'app. */
  exportBackup(now = this.#now()) {
    return swiftJSON({ version: 1, exportedAt: iso(now), exams: this.exams });
  }

  /** Sostituisce tutti i dati con quelli del backup; accetta anche un exams.json dell'app. */
  importBackup(text) {
    let imported;
    try {
      const object = parseJSON(text);
      if (Array.isArray(object)) {
        imported = decodeExamList(object);
      } else {
        if (!object || typeof object.version !== 'number') throw new DecodeError('backup');
        isoOf(object.exportedAt);
        imported = decodeExamList(object.exams);
      }
    } catch {
      throw new BackupError();
    }
    // Il backup sostituisce tutto, anche sugli altri dispositivi: gli esami assenti risultano eliminati.
    const importedIDs = new Set(imported.map((exam) => exam.id));
    const stamp = this.#timestamp();
    const deletions = { ...this.deletions };
    for (const exam of this.exams) {
      if (!importedIDs.has(exam.id)) deletions[exam.id] = stamp;
    }
    for (const id of importedIDs) delete deletions[id];
    this.deletions = deletions;
    this.exams = unique(imported).map((exam) => ({ ...this.#normalized(exam), modifiedAt: stamp }));
    this.#assignMissingColors();
    // Un ripristino esplicito sostituisce anche un file che non si riusciva a leggere.
    this.#isReadBlocked = false;
    this.#save();
  }

  // MARK: Persistenza

  #mutate(id, change) {
    const index = this.exams.findIndex((exam) => exam.id === id);
    if (index === -1) return;
    const draft = structuredClone(this.exams[index]);
    change(draft);
    const exam = this.#normalized(draft);
    exam.modifiedAt = this.#stamp(this.exams[index].modifiedAt);
    const exams = [...this.exams];
    exams[index] = exam;
    this.exams = exams;
    this.#save();
  }

  /** Adesso, al secondo: è la precisione con cui le date vengono salvate. */
  #timestamp() {
    return iso(this.#now());
  }

  /** Data di modifica sempre successiva a quella precedente (orologio logico). */
  #stamp(previous) {
    const now = this.#timestamp();
    if (!previous) return now;
    const after = iso(new Date(new Date(previous).getTime() + 1000));
    return after > now ? after : now;
  }

  /** Date a mezzogiorno e scadenze dei task non oltre il giorno dell'esame. */
  #normalized(exam) {
    const result = {
      ...exam,
      tasks: exam.tasks.map((task) => ({ ...task, subtasks: (task.subtasks ?? []).map((sub) => ({ ...sub })) })),
    };
    result.date = isoOf(noon(result.date));
    if (result.startTime !== null && result.startTime !== undefined
      && !(Number.isInteger(result.startTime) && result.startTime >= 0 && result.startTime < 24 * 60)) {
      result.startTime = null;
    }
    for (const task of result.tasks) {
      const due = isoOf(noon(task.dueDate));
      task.dueDate = result.isScheduled && due > result.date ? result.date : due;
      // Un task con checklist è fatto quando lo sono tutte le voci.
      if (task.subtasks.length > 0) task.isDone = task.subtasks.every((sub) => sub.isDone);
    }
    return result;
  }

  /** Assegna un colore agli esami che non ce l'hanno; vero se ha cambiato qualcosa. */
  #assignMissingColors() {
    let changed = false;
    // Copia modificata sul posto: `nextColorIndex` vede i colori appena assegnati.
    const exams = [...this.exams];
    this.exams = exams;
    for (let i = 0; i < exams.length; i++) {
      if (exams[i].colorIndex === null || exams[i].colorIndex === undefined) {
        exams[i] = { ...exams[i], colorIndex: this.nextColorIndex };
        changed = true;
      }
    }
    return changed;
  }

  async #load() {
    try {
      const text = await this.#persistence.readText(DELETIONS_FILE);
      if (text !== null) this.deletions = decodeDeletions(parseJSON(text));
    } catch {
      // Eliminazioni illeggibili: si riparte senza, come fa l'app iOS.
    }
    let text;
    try {
      text = await this.#persistence.readText(DATA_FILE);
    } catch (error) {
      console.error('ExamsTrack: lettura dei dati fallita', error);
      this.#isReadBlocked = true;
      this.lastError = 'readFailed';
      return;
    }
    if (text === null) return;
    try {
      this.exams = decodeExamList(parseJSON(text)).map((exam) => this.#normalized(exam));
      // Dati salvati prima dei colori assegnati: li completa e li salva una volta.
      if (this.#assignMissingColors()) this.#save();
    } catch (error) {
      if (!(error instanceof DecodeError)) throw error;
      try {
        await this.#persistence.remove(CORRUPT_FILE);
      } catch {
        // Non c'era.
      }
      try {
        await this.#persistence.rename(DATA_FILE, CORRUPT_FILE);
      } catch (renameError) {
        console.error('ExamsTrack: impossibile spostare i dati illeggibili', renameError);
      }
      this.exams = [];
      this.lastError = 'corruptedData';
    }
  }

  #save() {
    this.#emit();
    if (this.#isReadBlocked) {
      this.lastError = 'readFailed';
      this.#emit();
      return;
    }
    // Prima le eliminazioni: se l'app si chiudesse a metà, un esame eliminato non ricomparirebbe.
    const files = [
      { name: DELETIONS_FILE, text: swiftJSON(this.deletions) },
      { name: DATA_FILE, text: swiftJSON(this.exams) },
    ];
    this.#saving = this.#saving.then(() => this.#persistence.writeTexts(files)).catch((error) => {
      console.error('ExamsTrack: salvataggio fallito', error);
      this.lastError = 'saveFailed';
      this.#emit();
    });
  }
}
