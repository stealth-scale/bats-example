<!--
The title takes the form of a commit subject, because the merge uses it:
`type(scope): summary`, in the imperative, under 60 characters.
-->

## What changed

<!--
Open with a paragraph only where a reader would otherwise ask why this is one
pull request. Then one bullet per change, naming the module or the test it touches.
-->

-

## How it was checked

<!--
The output of `make check`. Name anything you could not check here and say why,
so a reviewer knows what CI is carrying.
-->

## Checklist

- [ ] `make check` passes.
- [ ] New tests are named `subject: case -> expectation` and load the `example` harness.
