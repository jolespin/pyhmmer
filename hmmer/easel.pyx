# coding: utf-8
# cython: language_level=3, linetrace=True

# --- C imports --------------------------------------------------------------

from libc.stdint cimport uint32_t

cimport libeasel
cimport libeasel.alphabet
cimport libeasel.sq
cimport libeasel.sqio


# --- Python imports ---------------------------------------------------------

import os
import warnings

from .errors import AllocationError, UnexpectedError


# --- Cython classes ---------------------------------------------------------

cdef class Alphabet:

    # --- Default constructors -----------------------------------------------

    cdef _init_default(self, int ty):
        self._abc = libeasel.alphabet.esl_alphabet_Create(ty)
        if not self._abc:
            raise AllocationError("ESL_ALPHABET")

    @classmethod
    def amino(cls):
        """Create a default Aminoacid alphabet.
        """
        cdef Alphabet alphabet = Alphabet.__new__(Alphabet)
        alphabet._init_default(libeasel.alphabet.eslAMINO)
        return alphabet

    @classmethod
    def dna(cls):
        """Create a default DNA alphabet.
        """
        cdef Alphabet alphabet = Alphabet.__new__(Alphabet)
        alphabet._init_default(libeasel.alphabet.eslDNA)
        return alphabet

    @classmethod
    def rna(cls):
        """Create a default RNA alphabet.
        """
        cdef Alphabet alphabet = Alphabet.__new__(Alphabet)
        alphabet._init_default(libeasel.alphabet.eslRNA)
        return alphabet

    # def __init__(self, str alphabet, int K, int Kp):
    #     buffer = alphabet.encode('ascii')
    #     self._alphabet = libeasel.alphabet.esl_alphabet_CreateCustom(<char*> buffer, K, Kp)
    #     if not self._alphabet:
    #         raise AllocationError("ESL_ALPHABET")

    # --- Magic methods ------------------------------------------------------

    def __cinit__(self):
        self._abc = NULL

    def __dealloc__(self):
        libeasel.alphabet.esl_alphabet_Destroy(self._abc)

    def __repr__(self):
        if self._abc.type == libeasel.alphabet.eslRNA:
            return "Alphabet.rna()"
        elif self._abc.type == libeasel.alphabet.eslDNA:
            return "Alphabet.dna()"
        elif self._abc.type == libeasel.alphabet.eslAMINO:
            return "Alphabet.amino()"
        else:
            return "Alphabet({!r}, K={!r}, Kp={!r})".format(
                self._abc.sym.decode('ascii'),
                self._abc.K,
                self._abc.Kp
            )

    def __eq__(self, Alphabet other):
        if other is None:
            return False
        return self._abc.type == other._abc.type   # FIXME



cdef class Sequence:
    """A biological sequence with some associated metadata.

    Todo:
        Make `TextSequence` and `DigitalSequence` subclasses that expose the
        right parts of the API without confusing the user.
    """

    # --- Magic methods ------------------------------------------------------

    def __cinit__(self):
        self._sq = NULL

    def __init__(self, name=None, sequence=None, description=None, accession=None, secondary_structure=None):

        cdef char* name_ptr = b""
        cdef char* seq_ptr  = b""
        cdef char* desc_ptr = NULL
        cdef char* acc_ptr  = NULL
        cdef char* ss_ptr   = NULL

        if name is not None:
            name_ptr = <char*> name
        if description is not None:
            desc_ptr = <char*> description
        if accession is not None:
            acc_ptr = <char*> accession
        if sequence is not None:
            seq_ptr = <char*> sequence
        if secondary_structure is not None:
            ss_ptr = <char*> secondary_structure

        self._sq = libeasel.sq.esl_sq_CreateFrom(name_ptr, seq_ptr, desc_ptr, acc_ptr, ss_ptr)
        if not self._sq:
            raise AllocationError("ESL_SQ")

    def __dealloc__(self):
        libeasel.sq.esl_sq_Destroy(self._sq)

    def __eq__(self, Sequence other):
        return libeasel.sq.esl_sq_Compare(self._sq, other._sq) == libeasel.eslOK

    # --- Properties ---------------------------------------------------------

    @property
    def accession(self):
        """`str` or `None`: The accession of the sequence, if any.
        """
        accession = <bytes> self._sq.acc
        return accession or None

    @accession.setter
    def accession(self, accession):
        if accession is None:
            accession = b""
        cdef int status = libeasel.sq.esl_sq_SetAccession(self._sq, <const char*> accession)
        if status == libeasel.eslEMEM:
            raise AllocationError("char*")
        elif status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_SetAccession")

    @property
    def name(self):
        """`bytes`: The name of the sequence.
        """
        return <bytes> self._sq.name

    @name.setter
    def name(self, bytes name):
        cdef int status = libeasel.sq.esl_sq_SetName(self._sq, <const char*> name)
        if status == libeasel.eslEMEM:
            raise AllocationError("char*")
        elif status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_SetName")

    @property
    def description(self):
        """`bytes`: The description of the sequence.
        """
        return <bytes> self._sq.desc

    @description.setter
    def description(self, desc):
        cdef int status = libeasel.sq.esl_sq_SetDesc(self._sq, <const char*> desc)
        if status == libeasel.eslEMEM:
            raise AllocationError("char*")
        elif status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_SetDesc")

    @property
    def source(self):
        """`bytes`: The source of the sequence, if any.
        """
        return <bytes> self._sq.source

    @source.setter
    def source(self, src):
        if src is None:
            src = b""
        cdef int status = libeasel.sq.esl_sq_SetSource(self._sq, <const char*> src)
        if status == libeasel.eslEMEM:
            raise AllocationError("char*")
        elif status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_SetSource")

    # --- Methods ------------------------------------------------------------

    def checksum(self):
        """Calculate a 32-bit checksum for the sequence.
        """
        cdef uint32_t checksum = 0
        cdef int status = libeasel.sq.esl_sq_Checksum(self._sq, &checksum)
        if status == libeasel.eslOK:
            return checksum
        else:
            raise UnexpectedError(status, "esl_sq_Checksum")

    def clear(self):
        """Reinitialize the sequence for re-use.
        """
        assert self._sq != NULL

        cdef int status = libeasel.sq.esl_sq_Reuse(self._sq)
        if status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_Reuse")



cdef class SequenceFile:

    _formats = {
        "fasta": libeasel.sqio.eslSQFILE_FASTA,
        "embl": libeasel.sqio.eslSQFILE_EMBL,
        "genbank": libeasel.sqio.eslSQFILE_GENBANK,
        "ddbj": libeasel.sqio.eslSQFILE_DDBJ,
        "uniprot": libeasel.sqio.eslSQFILE_UNIPROT,
        "ncbi": libeasel.sqio.eslSQFILE_NCBI,
        "daemon": libeasel.sqio.eslSQFILE_DAEMON,
        "hmmpgmd": libeasel.sqio.eslSQFILE_DAEMON,
        "fmindex": libeasel.sqio.eslSQFILE_FMINDEX,
    }


    # --- Class methods ------------------------------------------------------

    @classmethod
    def parse(cls, bytes buffer, str format):
        cdef Sequence seq = Sequence.__new__(Sequence)
        seq._sq = libeasel.sq.esl_sq_Create()
        if not seq._sq:
            raise AllocationError("ESL_SQ")
        return cls.parseinto(seq, buffer, format)

    @classmethod
    def parseinto(cls, Sequence seq, bytes buffer, str format):
        assert seq._sq != NULL

        cdef int fmt = libeasel.sqio.eslSQFILE_UNKNOWN
        if format is not None:
            fmt = cls._formats.get(format.lower())
            if fmt is None:
                raise ValueError("Invalid sequence format: {!r}".format(format))

        cdef int status = libeasel.sqio.esl_sqio_Parse(buffer, len(buffer), seq._sq, fmt)
        if status == libeasel.eslEFORMAT:
            raise AllocationError("")
        elif status == libeasel.eslOK:
            return seq
        else:
            raise UnexpectedError(status, "esl_sqio_Parse")


    # --- Magic methods ------------------------------------------------------

    def __cinit__(self):
        self._alphabet = None
        self._sqfp = NULL

    def __init__(self, str file, str format=None):
        cdef int fmt = libeasel.sqio.eslSQFILE_UNKNOWN
        if format is not None:
            fmt = self._formats.get(format.lower())
            if fmt is None:
                raise ValueError("Invalid sequence format: {!r}".format(format))

        cdef bytes fspath = os.fsencode(file)
        cdef int status = libeasel.sqio.esl_sqfile_Open(fspath, fmt, NULL, &self._sqfp)
        if status == libeasel.eslENOTFOUND:
            raise FileNotFoundError(2, "No such file or directory: {!r}".format(file))
        elif status == libeasel.eslEMEM:
            raise AllocationError("ESL_SQFILE")
        elif status == libeasel.eslEFORMAT:
            if format is None:
                raise ValueError("Could not determine format of file: {!r}".format(file))
            else:
                raise EOFError("Sequence file appears to be empty: {!r}")
        elif status != libeasel.eslOK:
            raise UnexpectedError(status, "esl_sq_Checksum")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def __dealloc__(self):
        if self._sqfp:
            warnings.warn("unclosed sequence file", ResourceWarning)
            self.close()

    def __iter__(self):
        return self

    def __next__(self):
        seq = self.read()
        if seq is None:
            raise StopIteration()
        return seq


    # --- Read methods -------------------------------------------------------

    cpdef Sequence read(self):
        """Read the next sequence from the file.

        Returns:
            `Sequence`: The next sequence in the file, or `None` if all
            sequences were read from the file.

        Hint:
            This method allocates a new sequence, which is not efficient in
            case the sequences are being read within a tight loop. Use
            `readinto` with an already initialized `Sequence` if you wish to
            recycle the buffers

        """
        cdef Sequence seq = Sequence.__new__(Sequence)
        seq._sq = libeasel.sq.esl_sq_Create()
        if not seq._sq:
            raise AllocationError("ESL_SQ")
        return self.readinto(seq)

    cpdef Sequence read_info(self):
        """Read info from the next sequence in the file.
        """
        cdef Sequence seq = Sequence.__new__(Sequence)
        seq._sq = libeasel.sq.esl_sq_Create()
        if not seq._sq:
            raise AllocationError("ESL_SQ")
        return self.readinto_info(seq)

    cpdef Sequence read_seq(self):
        """Read the next sequence from the file, without loading metadata.
        """
        cdef Sequence seq = Sequence.__new__(Sequence)
        seq._sq = libeasel.sq.esl_sq_Create()
        if not seq._sq:
            raise AllocationError("ESL_SQ")
        return self.readinto_seq(seq)

    cpdef Sequence readinto(self, Sequence seq):
        """Read the next sequence from the file, using ``seq`` to store data.

        Returns:
            `Sequence`: A reference to ``seq``, or `None` if no sequences are
            left in the file.

        Example:
            Use `SequenceFile.readinto` to loop over the sequences in a file
            while recycling the same `Sequence` buffer:

            >>> with SequenceFile("tests/data/seqs/ecori.fa") as sf:
            ...     seq = Sequence()
            ...     while sf.readinto(seq) is not None:
            ...         # ... process seq here ... #
            ...         seq.clear()

        """
        assert seq._sq != NULL

        if self._sqfp == NULL:
            raise ValueError("I/O operation on closed file.")

        cdef int status = libeasel.sqio.esl_sqio_Read(self._sqfp, seq._sq)
        if status == libeasel.eslOK:
            return seq
        elif status == libeasel.eslEOF:
            return None
        elif status == libeasel.eslEFORMAT:
            msg = <bytes> libeasel.sqio.esl_sqfile_GetErrorBuf(self._sqfp)
            raise ValueError("Could not parse file: {}".format(msg.decode()))
        else:
            raise UnexpectedError(status, "esl_sqio_Read")

    cpdef Sequence readinto_info(self, Sequence seq):
        """Read info from the next sequence, using ``seq`` to store metadata.
        """
        assert seq._sq != NULL

        if self._sqfp == NULL:
            raise ValueError("I/O operation on closed file.")

        cdef int status = libeasel.sqio.esl_sqio_ReadInfo(self._sqfp, seq._sq)
        if status == libeasel.eslOK:
            return seq
        elif status == libeasel.eslEOF:
            return None
        elif status == libeasel.eslEFORMAT:
            msg = <bytes> libeasel.sqio.esl_sqfile_GetErrorBuf(self._sqfp)
            raise ValueError("Could not parse file: {}".format(msg.decode()))
        else:
            raise UnexpectedError(status, "esl_sqio_ReadInfo")

    cpdef Sequence readinto_seq(self, Sequence seq):
        """Read the next sequence into ``seq``, without loading metadata.
        """
        assert seq._sq != NULL

        if self._sqfp == NULL:
            raise ValueError("I/O operation on closed file.")

        cdef int status = libeasel.sqio.esl_sqio_ReadSequence(self._sqfp, seq._sq)
        if status == libeasel.eslOK:
            return seq
        elif status == libeasel.eslEOF:
            return None
        elif status == libeasel.eslEFORMAT:
            msg = <bytes> libeasel.sqio.esl_sqfile_GetErrorBuf(self._sqfp)
            raise ValueError("Could not parse file: {}".format(msg.decode()))
        else:
            raise UnexpectedError(status, "esl_sqio_ReadSequence")


    # --- Fetch methods ------------------------------------------------------

    cpdef Sequence fetch(self, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetch")

    cpdef Sequence fetchinto(self, Sequence seq, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetchinto")

    cpdef Sequence fetch_info(self, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetchinto")

    cpdef Sequence fetchinto_info(self, Sequence seq, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetchinto")

    cpdef Sequence fetch_seq(self, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetchinto")

    cpdef Sequence fetchinto_seq(self, Sequence seq, bytes key):
        raise NotImplementedError("TODO SequenceFile.fetchinto")


    # --- Utils --------------------------------------------------------------

    cpdef void close(self):
        libeasel.sqio.esl_sqfile_Close(self._sqfp)
        self._sqfp = NULL

    cpdef Alphabet guess_alphabet(self):
        """Guess the alphabet of an open `SequenceFile`.

        This method tries to guess the alphabet of a sequence file by
        inspecting the first sequence in the file. It returns the alphabet,
        or `None` if the file alphabet cannot be reliably guessed.

        Raises:
            EOFError: if the file is empty.
            OSError: if a parse error occurred.
            ValueError: if this methods is called after the file was closed.

        """

        if self._sqfp == NULL:
            raise ValueError("I/O operation on closed file.")

        cdef int ty = 0
        cdef int status = libeasel.sqio.esl_sqfile_GuessAlphabet(self._sqfp, &ty)
        if status == libeasel.eslOK:
            alphabet = Alphabet.__new__(Alphabet)
            alphabet._init_default(ty)
            return alphabet
        elif status == libeasel.eslENOALPHABET:
            return None
        elif status == libeasel.eslENODATA:
            raise EOFError("Sequence file appears to be empty.")
        elif status == libeasel.eslEFORMAT:
            msg = <bytes> libeasel.sqio.esl_sqfile_GetErrorBuf(self._sqfp)
            raise ValueError("Could not parse file: {}".format(msg.decode()))

        return None

    cpdef void set_digital(self, Alphabet alphabet):
        """Set the `SequenceFile` to read in digital mode with ``alphabet``.

        This method can be called even after the first sequences have been
        read; it only affects subsequent sequences in the file.

        """
        if self._sqfp == NULL:
            raise ValueError("I/O operation on closed file.")

        cdef int status = libeasel.sqio.esl_sqfile_SetDigital(self._sqfp, alphabet._abc)
        if status == libeasel.eslOK:
            self._alphabet = alphabet
        else:
            raise UnexpectedError(status, "esl_sqfile_SetDigital")
