"""
This block reports instances of core arguments and the observable coding (such as case and agreement)
so that they can be later counted and show what is the prevailing strategy.
"""
import re
from udapi.core.block import Block

class CoreCoding(Block):

    def __init__(self, arg='all', verbform=True, **kwargs):
        """
        Create the my.CoreCoding block instance.

        Args:
        arg=subj|obj|iobj|all|agreement: are we collecting subjects, or objects, or verbal agreement features? (We should collect them separately if we want to compute percentage of each strategy.)
        verbform=1: the language uses the VerbForm feature to distinguish finite and nonfinite verbs
        """
        super().__init__(**kwargs)
        self.arg = arg
        self.verbform = verbform

    def process_node(self, node):
        # Do this from the perspective of the predicates (so that we can check also missing arguments).
        # Not all predicates are verbs, so we will test whether this is a clausal head (root, csubj, ccomp, xcomp, advcl, acl).
        # Possible problem: Coordination of clauses, we will only recognize the first clause (or there will be shared arguments which we will not see).
        if node.udeprel in ['root', 'csubj', 'ccomp', 'xcomp', 'advcl', 'acl']:
            # Is this a finite clause? Either the predicate is a finite verb, or there is an auxiliary which is a finite verb.
            # Because of past tense in Czech (which does not use auxiliaries in 3rd person), we include participles in finite clauses.
            # What we exclude is infinitives, converbs, and verbal nouns.
            auxiliaries = [x for x in node.children if x.udeprel in ['aux', 'cop']]
            if self.verbform:
                clausetype = 'nonfin'
                if node.feats['VerbForm'] in ['Fin', 'Part']:
                    clausetype = 'finite'
                else:
                    if any([x.feats['VerbForm'] in ['Fin', 'Part'] for x in auxiliaries]):
                        clausetype = 'finite'
            else:
                clausetype = ''
            tagnodes = {'V': node}
            # Find the subject (if present).
            subjects = [x for x in node.children if x.udeprel in ['nsubj', 'csubj']]
            if subjects:
                tagnodes['S'] = subjects[0]
            if self.arg in ['subj', 'all']:
                if subjects:
                    subjtype = subjects[0].deprel + ' ' + self.examine_argument(subjects[0])
                    subjtype += ' ' + self.get_order_tag(tagnodes)
                else:
                    subjtype = 'emptysubj'
                print("SUBJECT %s %s" % (clausetype, subjtype))
            # Find the object (if present).
            objects = [x for x in node.children if x.udeprel in ['obj', 'ccomp']]
            if objects:
                tagnodes['O'] = objects[0]
            if self.arg in ['obj', 'all']:
                if objects:
                    objtype = objects[0].deprel + ' ' + self.examine_argument(objects[0])
                    objtype += ' ' + self.get_order_tag(tagnodes)
                    print("OBJECT %s" % objtype)
            if self.arg in ['iobj', 'all']:
                # Find the indirect object (if present).
                iobjects = [x for x in node.children if x.udeprel == 'iobj']
                if iobjects:
                    tagnodes['I'] = iobjects[0]
                    iobjtype = iobjects[0].deprel + ' ' + self.examine_argument(iobjects[0])
                    iobjtype += ' ' + self.get_order_tag(tagnodes)
                    print("IOBJECT %s" % iobjtype)
            # Check agreement morphology on the verb.
            if self.arg in ['agreement', 'all']:
                agreements = []
                verbal_nodes = []
                if node.upos in ['VERB', 'AUX']:
                    verbal_nodes.append(node)
                verbal_nodes += auxiliaries
                for n in verbal_nodes:
                    agreement_features = [x + '=' + n.feats[x] for x in n.feats if re.match(r"^(Person|Number|Clusivity|Gender|Animacy|NounClass|Polite)(\[|$)", x)]
                    if agreement_features:
                        agreements.append('|'.join(agreement_features))
                print("AGREEMENT %s %s" % (clausetype, '|||'.join(agreements)))

    def examine_argument(self, node):
        # UPOS: NOUN+PROPN vs. PRON+DET vs. OTHER
        if node.upos in ['NOUN', 'PROPN']:
            upos = 'NOUN'
        elif node.upos in ['PRON', 'DET']:
            upos = 'PRON'
        else:
            upos = 'OTHER'
        # Morphological case
        if node.feats['Case']:
            case = node.feats['Case']
        else:
            case = 'NoCase'
        # Adpositions
        adpositions = [x for x in node.children if x.udeprel == 'case']
        ###!!! For each adposition, we should also search for its fixed children.
        info = [upos] + [self.get_lemma(x) for x in adpositions] + [case]
        return '+'.join(info)

    def get_lemma(self, node):
        if node.lemma == '_' or node.lemma == '':
            translit = node.misc['Translit'].lower()
            return translit if translit != '' else node.form.lower()
        else:
            translit = node.misc['LTranslit']
            return translit if translit != '' else node.lemma

    def get_order_tag(self, tagnodes):
        """
        Takes a dictionary where a string key (e.g., 'S') points to a node.
        Returns a string of tags ordered following the nodes' ord values.
        For example, it could be 'SOV' (meaning subject-object-verb).
        """
        return ''.join(sorted(tagnodes.keys(), key=lambda x: tagnodes[x].ord))
