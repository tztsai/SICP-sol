#lang racket/base

(require "sicp-lang.rkt")

;; utils
(define (type-tag exp)
  (car exp))

(define (make-table)
  (let ((table (list '*table*)))
    (define (lookup key)
      (let ((record (assoc key (cdr table))))
        (if record
            (cdr record)
            false)))
    (define (insert! key val)
      (let ((record (assoc key (cdr table))))
        (if record
            (set-cdr! record val)
            (set-cdr! table
                      (cons (cons key val)
                            (cdr table))))))
    (define (dispatch m)
      (cond ((eq? m 'lookup) lookup)
            ((eq? m 'insert!) insert!)
            (else (error "unknown operation: TABLE" m))))
    dispatch))

(define *T* (make-table))
(define put (*T* 'insert!))
(define get (*T* 'lookup))


;; 4.1.1

(define (Eval exp . env)
  (let ((env (if (null? env) Global (car env))))
    (cond ((self-evaluating? exp) exp)
          ((variable? exp) (lookup-variable-value exp env))
          ((quoted? exp) (text-of-quotation exp))
          ((assignment? exp) (eval-assignment exp env))
          ((definition? exp) (eval-definition exp env))
          ((if? exp) (eval-if exp env))
          ((lambda? exp)
           (make-procedure (lambda-parameters exp)
                           (lambda-body exp)
                           env))
          ((begin? exp)
           (eval-sequence (begin-actions exp) env))
          ((cond? exp) (Eval (cond->if exp) env))
          ((application? exp)
           (Apply (Eval (operator exp) env)
                  (list-of-values (operands exp) env)))
          (else
           (error "Unknown expression type - EVAL" exp)))))

(define (Apply procedure arguments)
  (cond ((primitive-procedure? procedure)
         (apply-primitive-procedure procedure arguments))
        ((compound-procedure? procedure)
         (eval-sequence
          (procedure-body procedure)
          (extend-environment
           (procedure-parameters procedure)
           arguments
           (procedure-environment procedure))))
        (else
         (error "Unknown procedure type - APPLY" procedure))))


(define (list-of-values exps env)
  (if (no-operands? exps)
      '()
      (cons (Eval (first-operand exps) env)
            (list-of-values (rest-operands exps) env))))

(define (eval-if exp env)
  (if (true? (Eval (if-predicate exp) env))
      (Eval (if-consequent exp) env)
      (Eval (if-alternative exp) env)))

(define (eval-sequence exps env)
  (cond ((last-exp? exps) (Eval (first-exp exps) env))
        (else (Eval (first-exp exps) env)
              (eval-sequence (rest-exps exps) env))))

(define (eval-assignment exp env)
  (set-variable-value! (assignment-variable exp)
                       (Eval (assignment-value exp) env)
                       env)
  'ok)

(define (eval-definition exp env)
  (define-variable! (definition-variable exp)
    (Eval (definition-value exp) env)
    env)
  'ok)

(define (eval-lambda exp env)
  (make-procedure (lambda-parameters exp)
                  (lambda-body exp)
                  env))

(define (eval-begin exp env)
  (eval-sequence (begin-actions exp) env))

(define (eval-cond exp env)
  (Eval (cond->if exp) env))


;; Ex 4.1
(define (list-of-values-eval-from-left exps env)
  (if (no-operands? exps)
      '()
      (let ((first-val (Eval (first-operand exps) env)))
        (cons first-val
              (list-of-values-eval-from-left (rest-operands exps) env)))))

(define (list-of-values-eval-from-right exps env)
  (if (no-operands? exps)
      '()
      (let ((rest-vals (list-of-values-eval-from-right (rest-operands exps) env)))
        (cons (Eval (first-operand exps) env)
              rest-vals))))


;; 4.1.2
;  representation of expressions

(define (self-evaluating? exp)
  (cond ((number? exp) true)
        ((string? exp) true)
        (else false)))

(define (variable? exp) (symbol? exp))

(define (tagged-list? exp tag)
  (if (pair? exp)
      (eq? (car exp) tag)
      false))

(define (quoted? exp)
  (tagged-list? exp 'quote))
(define (text-of-quotation exp) (cadr exp))

(define (assignment? exp)
  (tagged-list? exp 'set!))
(define (assignment-variable exp) (cadr exp))
(define (assignment-value exp) (caddr exp))

(define (definition? exp)
  (tagged-list? exp 'define))
(define (definition-variable exp)
  (if (symbol? (cadr exp))
      (cadr exp)
      (caadr exp)))
(define (definition-value exp)
  (if (symbol? (cadr exp))
      (caddr exp)
      (make-lambda (cdadr exp)   ; formal parameters
                   (cddr exp)))) ; body

(define (lambda? exp) (tagged-list? exp 'lambda))
(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))
(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)))

(define (if? exp) (tagged-list? exp 'if))
(define (if-predicate exp) (cadr exp))
(define (if-consequent exp) (caddr exp))
(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
      (cadddr exp)
      'false))
(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))

(define (begin? exp) (tagged-list? exp 'begin))
(define (begin-actions exp) (cdr exp))
(define (make-begin seq) (cons 'begin seq))

(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))
(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq))))

(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))
(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))

; special forms derived from other special forms
(define (cond? exp) (tagged-list? exp 'cond))
(define (cond-clauses exp) (cdr exp))
(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else))
(define (cond-predicate clause) (car clause))
(define (cond-actions clause) (cdr clause))
(define (cond->if exp)
  (expand-clauses (cond-clauses exp)))

(define (expand-clauses clauses)
  (if (null? clauses)
      'false ; no else clause
      (let ((first (car clauses))
            (rest (cdr clauses)))
        (if (cond-else-clause? first)
            (if (null? rest)
                (sequence->exp (cond-actions first))
                (error "ELSE clause isn't last - COND->IF"
                       clauses))
            (make-if (cond-predicate first)
                     (sequence->exp (cond-actions first))
                     (expand-clauses rest))))))


;; Ex 4.2
(define (Louis-eval exp env)
  (cond ((Louis-application? exp)
         (Apply (Eval (operator exp) env)
                (list-of-values (operands exp) env)))
        ((self-evaluating? exp) exp)
        ((variable? exp) (lookup-variable-value exp env))
        ((quoted? exp) (text-of-quotation exp))
        ((assignment? exp) (eval-assignment exp env))
        ((definition? exp) (eval-definition exp env))
        ((if? exp) (eval-if exp env))
        ((lambda? exp)
         (make-procedure (lambda-parameters exp)
                         (lambda-body exp)
                         env))
        ((begin? exp)
         (eval-sequence (begin-actions exp) env))
        ((cond? exp) (Eval (cond->if exp) env))
        (else
         (error "Unknown expression type - EVAL" exp))))

(define (Louis-application? exp) (tagged-list? exp 'call))
(define (Louis-operator exp) (cadr exp))
(define (Louis-operands exp) (cddr exp))


;; Ex 4.3
(define (dispatch-eval exp . env)
  (let ((env (if (null? env) Global (car env))))
    (cond ((self-evaluating? exp) exp)
          ((variable? exp) (lookup-variable-value exp env))
          ((get (type-tag exp))
           (apply (get (type-tag exp)) (list exp env)))
          ((application? exp)
           (Apply (Eval (operator exp) env)
                  (list-of-values (operands exp) env)))
          (else
           (error "Unknown expression type - EVAL" exp)))))

(define (install-eval-rules)
  (put 'quote (lambda (exp env) (text-of-quotation exp)))
  (put 'set! eval-assignment)
  (put 'define eval-definition)
  (put 'if eval-if)
  (put 'lambda eval-lambda)
  (put 'begin eval-begin)
  (put 'cond eval-cond)
  (put 'let eval-let)
  'ok)

(define (use-dispatch)
  (set! Eval dispatch-eval)
  (install-eval-rules)
  (install-logic-ops)
  (install-delete!)
  (install-let*)
  (install-named-let)
  (install-quasiquote)
  'ok)

;; Ex 4.4
(define (install-logic-ops)
  (define (xnor x y)
    (if x y (not y)))
  
  (define (eval-until ops env bool)
    (if (null? ops)
        (not bool)
        (let ((op (Eval (first-operand ops) env)))
          (if (or (null? (cdr ops)) (xnor bool op))
              op
              (eval-until (rest-operands ops) env bool)))))
  
  (define (eval-and exp env)
    (eval-until (operands exp) env #f))

  (define (eval-or exp env)
    (eval-until (operands exp) env #t))

  (define (eval-not exp env)
    (not (Eval exp env)))

  (define (and->if exp)
    (define (expand seq)
      (if (null? seq)
          'true
          (let ((first (car seq))
                (rest (cdr seq)))
            (if (null? rest)
                first
                (make-if first
                         (expand rest)
                         'false)))))
    (expand (cdr exp)))

  (define (or->if exp)
    (define (expand seq)
      (if (null? seq)
          'false
          (let ((first (car seq))
                (rest (cdr seq)))
            (if (null? rest)
                first
                (make-if first
                         'true
                         (expand rest))))))
    (expand (cdr exp)))

  (put 'and eval-and)
  (put 'or eval-or)
  (put 'not eval-not)
  ;(put 'and (eval-convert and->if))
  ;(put 'or (eval-convert or->if))
  'ok)

(define (eval-convert convert)
  (lambda (exp env)
    (Eval (convert exp) env)))


;; Ex 4.5
(define (add-cond-arrow)
  (define (new-expand-clauses clauses)
    (if (null? clauses)
        'false ; no else clause
        (let ((first (car clauses))
              (rest (cdr clauses)))
          (if (cond-else-clause? first)
              (if (null? rest)
                  (sequence->exp (cond-actions first))
                  (error "ELSE clause isn't last - COND->IF"
                         clauses))
              (make-if (cond-predicate first)
                       (if (cond-arrow-clause? first)
                           (invoke-arrow-clause first)
                           (sequence->exp (cond-actions first)))
                       (new-expand-clauses rest))))))
  (define (cond-arrow-clause? clause)
    (and (eq? (cadr clause) '=>)
         (null? (cdddr clause))))

  (define (invoke-arrow-clause clause)
    (let ((test (car clause))
          (recipient (caddr clause)))
      (list recipient test)))
  
  (set! expand-clauses new-expand-clauses))


;; Ex 4.6
(define (let->combination exp)
  (define (vars-exps binds)
    (if (null? binds)
        (cons '() '())
        (let ((var (caar binds))
              (exp (cadar binds))
              (rest (vars-exps (cdr binds))))
          (set-car! rest (cons var (car rest)))
          (set-cdr! rest (cons exp (cdr rest)))
          rest)))
  (let ((binds (cadr exp))
        (body (cddr exp)))
    (let ((vars-exps-pair (vars-exps binds)))
      (cons (make-lambda (car vars-exps-pair) body)
            (cdr vars-exps-pair)))))

(define eval-let (eval-convert let->combination))


;; Ex 4.7
(define (make-let binds body)
  (cons 'let (cons binds body)))

(define (let*->nested-lets exp)
  (define (convert binds body)
    (if (null? binds)
        body
        (make-let (list (car binds))
                  (convert (cdr binds) body))))
  (convert (cadr exp) (cddr exp)))

(define (install-let*)
  (put 'let* (eval-convert let*->nested-lets)))


;; Ex 4.8
(define (install-named-let)
  (define (new-let->combination exp)
    (define (vars-exps binds)
      (if (null? binds)
          (cons '() '())
          (let ((var (caar binds))
                (exp (cadar binds))
                (rest (vars-exps (cdr binds))))
            (set-car! rest (cons var (car rest)))
            (set-cdr! rest (cons exp (cdr rest)))
            rest)))
    (let* ((named (symbol? (cadr exp)))
           (name (if named (cadr exp) null))
           (binds (if named (caddr exp) (cadr exp)))
           (body (if named (cdddr exp) (cddr exp)))
           (vars-exps-pair (vars-exps binds))
           (vars (car vars-exps-pair))
           (exps (cdr vars-exps-pair)))
      (if named
          (let ((proc (make-lambda vars body)))
            (set! body (cons (list 'define name proc) body)))
          'pass)
      (cons (make-lambda vars body) exps)))
  (set! let->combination new-let->combination))


;; extra exerciese
(define (install-quasiquote)
  (define (eval-quasiquote exp env)
    (define (unquote exp)
      (if (pair? exp)
          (if (eq? (car exp) 'unquote)
              (Eval (cadr exp) env)
              (map unquote exp))
          exp))
    (unquote (cadr exp)))
  (put 'quasiquote eval-quasiquote))


;; 4.1.3 Evaluator data structures

(define (true? x)
  (not (eq? x false)))
(define (false? x)
  (eq? x false))

(define (make-procedure parameters body env)
  (list 'procedure parameters body env))

(define (compound-procedure? p)
  (tagged-list? p 'procedure))
(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))

; environment
(define (enclosing-environment env) (cdr env))
(define (first-frame env) (car env))

; frame
(define (make-frame variables values)
  (cons variables values))
(define (frame-variables frame) (car frame))
(define (frame-values frame) (cdr frame))

(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))))

(define (remove-binding-from-frame! var frame)
  (define (scan vars prev-vars vals prev-vals)
    (cond ((null? vars) #f)
          ((eq? var (car vars))
           (if (null? prev-vars)
               (begin (set-car! frame (cdr vars))
                      (set-cdr! frame (cdr vals)))
               (begin (set-cdr! prev-vars (cdr vars))
                      (set-cdr! prev-vals (cdr vals))))
           'ok)
          (else (scan (cdr vars) vars (cdr vals) vals))))
  (scan (frame-variables frame) null (frame-values frame) null))

(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
      (cons (make-frame vars vals) base-env)
      (if (< (length vars) (length vals))
          (error "Too many arguments supplied" vars vals)
          (error "Too few arguments supplied" vars vals))))

(define (lookup-variable-value var env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (car vals))
            (else (scan (cdr vars) (cdr vals)))))
    (if (null? env)
        (error "Unbound variable" var)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame)))))
  (env-loop env))

(define (set-variable-value! var val env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (if (null? env)
        (error "Unbound variable - SET!" var)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame)))))
  (env-loop env))

(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (add-binding-to-frame! var val frame))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (scan (frame-variables frame)
          (frame-values frame))))


;; Ex 4.11
(define (use-alternate-frame-repr)
  (define (make-binding var val)
    (cons var val))
  (define (binding-var binding)
    (car binding))
  (define (binding-val binding)
    (cdr binding))
  (define (rebind-val! binding val)
    (set-cdr! binding val))
  
  (define (add-binding-to-frame! var val frame)
    (set! frame (cons (make-binding var val) (cdr frame))))

  (define (extend-environment* bindings base-env)
    (cons bindings base-env))

  (define (lookup-variable-value* var env)
    (define (env-loop env)
      (define (scan frame)
        (cond ((null? frame)
               (env-loop (enclosing-environment env)))
              ((eq? var (binding-var (car frame)))
               (binding-val (car frame)))
              (else (scan (cdr frame)))))
      (if (null? env)
          (error "Unbound variable" var)
          (scan (first-frame env))))
    (env-loop env))

  (define (set-variable-value!* var val env)
    (define (env-loop env)
      (define (scan frame)
        (cond ((null? frame)
               (env-loop (enclosing-environment env)))
              ((eq? var (binding-var (car frame)))
               (rebind-val! (car frame) val))
              (else (scan (cdr frame)))))
      (if (null? env)
          (error "Unbound variable - SET!" var)
          (scan (first-frame env))))
    (env-loop env))

  (define (define-variable!* var val env)
    (display "Doing Ex 4.11...")
    (define (scan frame)
      (cond ((null? frame)
             (add-binding-to-frame! var val frame))
            ((eq? var (binding-var (car frame)))
             (rebind-val! (car frame) val))
            (else (scan (cdr frame)))))
    (scan (first-frame env)))

  (set! extend-environment extend-environment*)
  (set! lookup-variable-value lookup-variable-value*)
  (set! set-variable-value! set-variable-value!*)
  (set! define-variable! define-variable!*)
  'ok)


;; Ex 4.12
(define (env-op var val env when-found loop-up when-not-found)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (if loop-up
                 (env-loop (enclosing-environment env))
                 (when-not-found var val env)))
            ((eq? var (car vars))
             (when-found vals val))
            (else (scan (cdr vars) (cdr vals)))))      
    (if (null? env)
        (when-not-found var val env)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame)))))
  (env-loop env))

(define (more-abstract-env-ops)
  
  (define (lookup-variable-value* var env)
    (display "Doing Ex 4.12...")
    (env-op var null env
            (lambda (vals val) (car vals))
            true
            (lambda (var val env)
              (error "Unbound variable" var))))

  (define (set-variable-value!* var val env)
    (env-op var val env
            (lambda (vals val) (set-car! vals val))
            true
            (lambda (var val env)
              (error "Unbound variable - SET!" var))))

  (define (define-variable!* var val env)
    (env-op var val env
            (lambda (vals val) (set-car! vals val))
            false
            (lambda (vars val env)
              (add-binding-to-frame! var val (first-frame env)))))

  (set! lookup-variable-value lookup-variable-value*)
  (set! set-variable-value! set-variable-value!*)
  (set! define-variable! define-variable!*)

  (if (equal? (map Eval '((define x 1) x (set! x 2) x))
              '(ok 1 ok 2))
      'ok
      'failed))


;; Ex 4.13
(define (install-delete!)
  (define (delete! var env)
    (define (env-loop env)
      (define (scan frame)
        (if (remove-binding-from-frame! var frame)
            'ok
            (env-loop (enclosing-environment env))))
      (if (null? env)
          (error "Unbound variable - DELETE!" var)
          (scan (first-frame env))))
    (env-loop env))

  (define (eval-delete! exp env)
    (map (lambda (var) (delete! var env))
         (cdr exp)))
  
  (put 'delete! eval-delete!)

  ;test
  (map Eval '((define x 10)
              (define (f)
                (define x 19)
                (define y x)
                (delete! x)
                (let ((y -1))
                  (delete! y)
                  (list x y)))))
  (if (equal? (Eval '(f))
              (list 10 19))
      'ok
      'fail))

;; 4.1.4 Evaluator as a program

; primitives
(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive))

; builtin combined procedures
(define (map* proc lst)
  (map (lambda (exp) (Apply proc (list exp))) lst))

(define primitive-procedures
  `((car ,car)
    (cdr ,cdr)
    (caar ,caar)
    (cdar ,cdar)
    (cadr ,cadr)
    (cddr ,cddr)
    (caaar ,caaar)
    (cdaar ,cdaar)
    (cadar ,cadar)
    (cddar ,cddar)
    (caadr ,caadr)
    (cdadr ,cdadr)
    (caddr ,caddr)
    (cdddr ,cdddr)
    (caaaar ,caaaar)
    (cdaaar ,cdaaar)
    (cadaar ,cadaar)
    (cddaar ,cddaar)
    (caadar ,caadar)
    (cdadar ,cdadar)
    (caddar ,caddar)
    (cdddar ,cdddar)
    (caaadr ,caaadr)
    (cdaadr ,cdaadr)
    (cadadr ,cadadr)
    (cddadr ,cddadr)
    (caaddr ,caaddr)
    (cdaddr ,cdaddr)
    (cadddr ,cadddr)
    (cddddr ,cddddr)
    (cons ,cons)
    (null ,null)
    (null? ,null?)
    (eq? ,eq?)
    (equal? ,equal?)
    (memq ,memq)
    (set-car! ,set-car!)
    (set-cdr! ,set-cdr!)
    (+ ,+)
    (- ,-)
    (* ,*)
    (/ ,/)
    (= ,=)
    (list ,list)
    (pair? ,pair?)
    (list? ,list?)
    (symbol? ,symbol?)
    (number? ,number?)
    (string? ,string?)
    (apply ,Apply)
    (eval ,Eval)
    (length ,length)
    (assoc ,assoc)
    (error ,error)
    (display ,display)
    (newline ,newline)
    (read ,read)
    (put ,put)
    (get ,get)
    ; combined procedures below
    (map ,map*)
    ))
    

(define (primitive-implementation proc) (cadr proc))
(define (primitive-procedure-names)
  (map car primitive-procedures))
(define (primitive-procedure-objects)
  (map (lambda (proc) (list 'primitive (cadr proc)))
       primitive-procedures))

(define (apply-primitive-procedure proc args)
  (apply (primitive-implementation proc) args))


; setup the global environment
(define (setup-environment)
  (let ((initial-env
         (extend-environment (primitive-procedure-names)
                             (primitive-procedure-objects)
                             null)))
    (define-variable! 'true true initial-env)
    (define-variable! 'false false initial-env)
    initial-env))

(define Global (setup-environment))

; driver loop function
(define input-prompt "--- INPUT  ---")
(define output-prompt "--- OUTPUT ---")

(define (driver-loop)
  (prompt-for-input input-prompt)
  (let ((input (read)))
    (let ((output(Eval input)))
      (announce-output output-prompt)
      (user-print output)))
  (driver-loop))

(define (prompt-for-input string)
  (newline) (newline) (display string) (newline) (display "> "))

(define (announce-output string)
  (newline) (display string) (newline) (display "> "))

(define (user-print object)
  (if (compound-procedure? object)
      (display (list 'compound-procedure
                     (procedure-parameters object)
                     (procedure-body object)
                     '<procedure-env>))
      (display object)))

; start driver loop
(use-dispatch)
(display "Start M-Evaluator.")
(driver-loop)