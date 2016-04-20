#lang plai

;(load "data/hashT.rkt")
;;;;;;; INSTRUCTIONS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Upon running this code in DrRacket, it takes about 110-120 seconds to read in, parse
; (i.e. remove html tags, stop words, special characters) and tokenize the them.
;
; STEP 1 : Build the inverted index & vectorize documents by the following command >>
; (build-engine)
;
; STEP 2 : After building the search engine, queries can be issed with the following command >>
; (search "some words")
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; Special Characters to be excluded from the words
(define specialChars '(#\! #\" #\' #\$ #\% #\& #\( #\) #\* #\+ #\, #\- #\. #\: #\; #\= #\? #\@ #\[ #\\ #\] #\^ #\_ #\` #\{ #\| #\} #\~ #\_ #\# #\– #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9))

;; Reads file of title 'file-name' from the 'data/' directory (FileName -> [String])
(define (read-file file-name)
  (file->lines (string-append "data/" file-name)))

;; Removes Special Characters ([String] -> [String])
(define (clean-up str)
    (list->string (remove* specialChars (string->list str))))

;; Adds a space before and after '<' and '>' to separate tags
(define (tag-spacer x)
  (let ((chars (string->list x)))
    (cond
      [(null? chars) '()]
      [(or (eq? (car chars) #\<) (eq? (car chars) #\>)) (cons #\space (cons (car chars) (cons #\space (tag-spacer (list->string (cdr chars))))))]
      [else (cons (car chars) (tag-spacer (list->string (cdr chars))))])))


(define (tokenize-string str)
  (define in (open-input-string str))
  (let recur ((out (open-output-string)))
    (define c (read-char in))
    (cond ((eof-object? c)
           (list (get-output-string out)))
          ((or  (char=? c #\space) (char=? c #\tab))
           (cons (get-output-string out)
                 (recur (open-output-string))))
          (else (write-char c out) (recur out)))))


(define (trim xs)
  (cond
    [(null? xs) '()]
    [(not (or (string-contains? (car xs) "< style >") (string-contains? (car xs) "< script >"))) (cons (car xs) (trim (cdr xs)))]
    [else
     (let ((disjunct (or (is-member "< /style >" xs) (is-member "< /script >" xs))))
       (if (equal? disjunct #f)
           (rev-trim (cdr xs))
           (trim disjunct)))]))

(define (rev-trim xs)
  (cond
    [(null? xs) '()]
    [(or (string-contains? (car xs) "< style >") (string-contains? (car xs) "< script >")) (cons (car xs) (rev-trim (cdr xs)))]
    [else
     (let ((disjunct (or (is-member "< /script >" xs)  (is-member "< /style >" xs))))
       (if (equal? disjunct #f)
           (trim (cdr xs))
           (rev-trim disjunct)))]))

(define (de-tag list-of-tokens)
  (cond
    [(null? list-of-tokens) '()]
    [(not (equal? "<" (car list-of-tokens))) (cons (car list-of-tokens) (de-tag (cdr list-of-tokens)))]
    [else (de-tag (is-member ">" list-of-tokens))]))



(define (is-member x xs)
  (cond
    [(null? xs) #f]
    [(equal? (car xs) x) (cdr xs)]
    [else (is-member x (cdr xs))]))

(define (remove-stops xs )
  (remove* (pre-proc "stops.txt") xs))


;;;;;;;;;;;;;;;;;;;;;;;;; Compilation ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define (prep file-name)
  (map string-downcase (map list->string (map tag-spacer (map clean-up (read-file file-name))))))

(define (pre-proc file-name)
 (de-tag (flatten (map tokenize-string (trim (prep file-name))))))

(define (proc file-name)
  (remove-stops (pre-proc file-name)))
  ;(pre-proc file-name))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Term Statistics ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-type Stat
  (mtStat)
  (stat (docFreq number?) (termFreq number?) (postings hash?)))


;;;;;;;;;;;;;;;;;;;;;;;;;;; Dictionary - Build and Operations ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define dictionary (make-hash))

(define (hash word doc)
  (if (equal? (hash-ref dictionary word [(lambda ()#f)]) #f)

      ;The word is not in the dict. Create a fresh record
      (begin (hash-set! dictionary word (stat 1 1 (make-hash)))
             ;fetch hashtable of the new word and record document
             (hash-set! (stat-postings (get-stat word)) doc 1))

      
      ;The word is in the dictionary, just edit its stats
      (if (equal? (hash-ref (stat-postings (get-stat word)) doc [(lambda ()#f)]) #f)
          ;New Document - This document was not previously included in the postings
          (begin
            ;Increase DF for the term by 1, Increase Overall TF by 1
            (hash-set! dictionary word (stat (+ 1 (stat-docFreq (get-stat word))) (+ 1 (stat-termFreq (get-stat word))) (stat-postings (get-stat word))))

            ;Add a new entry into the postings
            (hash-set! (stat-postings (get-stat word)) doc 1))

            
          ;Same Document - This document already exists in the postings of the term
          (begin 
             ;Increase TF for the current doc by 1
             (hash-set! (stat-postings (get-stat word)) doc (+ 1 (hash-ref (stat-postings (get-stat word)) doc)))
             
             ;Increase Overall TF by 1
             (hash-set! dictionary word (stat (stat-docFreq (get-stat word)) (+ 1 (stat-termFreq (get-stat word))) (stat-postings (get-stat word))))))))


(define (get-stat word)
  (hash-ref dictionary word ))

(define (hash-doc xs doc-id)
  (cond
    [(null? xs) #t]
    [(or (equal? (string-length (car xs)) 0) (> (string-length (car xs)) 27)) (hash-doc (cdr xs) doc-id)]
    [else (begin (hash (car xs) doc-id) (hash-doc (cdr xs) doc-id))]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Filesystem -> Scheme ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define all-files (map path->string (directory-list "data/")))

(define (documents xs)
  (cond
    [(null? xs) '()]
    [else (if (or (equal? (car xs) ".DS_Store") (equal? (car xs) "stops.txt")) (documents (cdr xs)) (cons (car xs) (documents (cdr xs))))]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Docs -> Hash ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; List of names of all files available to process
(define universe (documents all-files))
;(define universe '())

; Process all availables documents into a (List of (List of Tokens))
(define universal-tokens
  (map proc universe))

; Accept Universal Tokens and a starting document-id (1) value, to build an Inverted Index
(define (hash-up doc-id list-docs)
  (cond
    [(null? list-docs) "Document indexing completed"]
    [else (begin
            (hash-doc (car list-docs) doc-id)
            (hash-up (+ 1 doc-id) (cdr list-docs)))]
    ))

; Put all the pieces together to get an Inverted Index
(define (index)
  (hash-up 1 universal-tokens))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; IDF Calculations ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (log10 n)
  (/ (log n) (log 10)))

(define (idf word)
  (if (equal? 0 (log10 (/ (length universe) (stat-docFreq (get-stat word)))))
      0.00001
      (log10 (/ (length universe) (stat-docFreq (get-stat word))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Vectorization of Docs ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define vectors (make-hash))


;; Processing document 1 & creating its vector
(define (dictionary-terms)
  (hash-keys dictionary))

; Creates vector for a document
(define (make-vector all-terms cur-doc)
  (cond
    [(null? all-terms) '()]
    [else
     (if (equal? (exists? (stat-postings (get-stat (car all-terms))) cur-doc) #t)
         ; Postings of this term contains current document

         (cons
          (*
           (idf (car all-terms)) ; IDF of this term
           (hash-ref (stat-postings (get-stat (car all-terms))) cur-doc));TF of this term in this doc
          (make-vector (cdr all-terms) cur-doc)) ;Recurse on the rest of the list

         ; Posting of this term DOESN't contain current docuemnt. Weight is 0
         (cons 0 (make-vector (cdr all-terms) cur-doc)))]))



; Returns a boolean corresponding to if a term exists in the HT.
(define (exists? ht word)
  (if (equal? (hash-ref ht word [(lambda ()#f)]) #f) #f #t))


; Vectorizes documents one by one
(define (vectorize-helper start max list)
  (if (equal? max 0)
      "Document vectorization process completed"
      (begin
        (hash-set! vectors start (normalize (make-vector list start)))
         (vectorize-helper (+ start 1) (- max 1) list))))

; Vectorize All Documents
(define (vectorize)
  (cond
    [(null? (dictionary-terms)) "Unsuccessful. Indexing is required before vectorization."]
    [else (vectorize-helper 1 (length universe) (dictionary-terms))]))


;Retrieves a vector from the hashtable
(define (get-vector x)
  (if (exists? vectors x)
      (hash-ref vectors x)
      "Specified document vector does not exist."))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Vector Similarity Calculations ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Normalize a vector
(define (normalize vect)
  (let ((length (sqrt (sum-of-squares vect))))
    (if (equal? length 0)
        (map (lambda (x) (/ x 1)) vect)
        (map (lambda (x) (/ x length)) vect))))


;(apply + (map * lst lst)))
(define (sum-of-squares lst)
  (cond
    [(null? lst) 0]
    [else (+ (* (car lst) (car lst)) (sum-of-squares (cdr lst)))]))


;; Vector-Vector Similarity
(define (sim d1 d2)
  (cond
    [(null? d1) 0]
    [else
     (+ (* (car d1) (car d2)) (sim (cdr d1) (cdr d2)))]))



;Get nth name
(define (get-doc-helper n list)                   
      (cond ((null? list) "Specified document does not exist.")             
            ((= n 0) (car list))              
            (else (get-doc-helper (- n 1) (cdr list)))))

;Get document name corresponding to id
(define (get-doc n)
  (get-doc-helper (- n 1) universe))


;;;;;;;;;;;;;;;;;;;;;;; QUERY Vectorization;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define q1 '("gold" "silver" "truck"))
(define cross (dictionary-terms))

(define (make-list size)
  (cond
    [(equal? size 0) '()]
    [else (cons 0 (make-list (- size 1)))]))

;; find index of an element in a list
(define (get-index word lst pos)
  (cond
    [(null? lst) -1]
    [(equal? word (car lst)) pos]
    [else (get-index word (cdr lst) (+ 1 pos))]))

;; Set nth element of a list
(define (replace-nth list n elem)
  (cond
    ((null? list) #t)
    ((eq? n 0) (cons elem (cdr list)))
    (#t (cons (car list) (replace-nth (cdr list) (- n 1) elem)))))


(define (vectorize-query query)
  (normalize (vectorize-query-helper query (make-list (length (dictionary-terms))) (dictionary-terms))))


(define (vectorize-query-helper query vector lst)
  (cond
    ((null? query) vector)
    (else
     (if (equal? (get-index (car query) lst 0) -1)
         (vectorize-query-helper (cdr query) vector lst)
         (let ((new-vect (replace-nth vector
                  (get-index (car query) lst 0)
                  (+ (get-doc-helper (get-index (car query) lst 0) vector) (idf (car query))))))
           (vectorize-query-helper (cdr query) new-vect lst))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Search Query for similarity with Docs ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define (search-helper query list-doc)
  (cond
    [(null? list-doc) '()]
    [else
     (cons (sim (get-vector (car list-doc)) query) (search-helper query (cdr list-doc)))]))

;;make list of document indices
(define (make-list-doc starter size)
  (cond
    [(equal? size 0) '()]
    [else (cons (+ 1 starter) (make-list-doc (+ 1 starter) (- size 1)))]))

(define (prep-query str)
  (remove-stops
   (tokenize-string (string-downcase (clean-up str)))))

;; Main search function for similarities 
(define (search query)
  (time (name-it (get-top-x 10 (qsort (make-sim-list (search-helper (vectorize-query (prep-query query)) (make-list-doc 0 (length universe))) 1))))))

;; Sort sim list
(define (qsort a)
  (if (empty? a)
    a
    (let ([p (car a)])
      (let ([tail (cdr a)])
        (let ([rev-grt (filter (lambda (x) (< (a-rec-sim-val x) (a-rec-sim-val p))) tail)])
          (let ([rev-lsr (filter (lambda (x) (>= (a-rec-sim-val x) (a-rec-sim-val p))) tail)])
            (append (qsort rev-lsr) (list p) (qsort rev-grt))))))))

;; Get top ten
(define (get-top-x how-many lst)
  (cond
    [(or (null? lst) (equal? 0 how-many)) '()]
    [else
      (cons (car lst) (get-top-x (- how-many 1) (cdr lst)))]))

;; get element names
(define (name-it lst)
  (cond
    [(null? lst) '()]
    [else
     (cons (get-doc-helper (- (a-rec-doc-id (car lst)) 1) universe) (name-it (cdr lst)))]))

;;;;;;;;;;;;; Similarity list for ranking ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-type SimDoc
  (a-rec (doc-id number?) (sim-val number?)))

(define (make-sim-list sim start)
  (cond
    [(null? sim) '()]
    [else
     (cons (a-rec start (car sim)) (make-sim-list (cdr sim) (+ 1 start)))]))

  
;;;;;;;;;;;;; BUILD SEARCH ENGINE ::::::::::::::::::::::::::
(define (build-engine)
  (begin (index)
         (vectorize)))